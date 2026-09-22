// ignore_for_file: prefer_initializing_formals, use_null_aware_elements

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:system_info2/system_info2.dart';

import 'device_context_config.dart';
import 'device_context_models.dart';

class DeviceContextService {
  // Keep the public named parameter "config" stable for package users.
  // ignore: prefer_initializing_formals
  DeviceContextService({
    DeviceContextConfig config = const DeviceContextConfig(),
  }) : _config = config;

  DeviceContextConfig _config;
  DeviceContextConfig get config => _config;

  /// Updates runtime device-context preferences and clears cached values so
  /// the next collection follows the new privacy/feature choices.
  void updateConfig(DeviceContextConfig config) {
    _config = config;
    clearCache();
  }

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final Geocoding _geocoding = Geocoding();

  final Map<String, _CacheEntry<Object?>> _cache =
      <String, _CacheEntry<Object?>>{};

  DeviceContextSnapshot? _lastSnapshot;

  DeviceContextSnapshot? get lastSnapshot => _lastSnapshot;

  void clearCache() {
    _cache.clear();
    _lastSnapshot = null;
  }

  /// Explicit permission request for host apps that expose a user-facing
  /// "Enable device location" toggle. DeviceContextConfig never requires this
  /// to be called when location is already granted.
  Future<bool> requestLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return false;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Returns true for prompts that can be answered primarily from enabled
  /// device context. Local device context can then be preferred over a generic
  /// public web search.
  bool canSatisfyPrompt(String prompt) {
    if (!config.enabled) return false;

    final intent = _DeviceIntent.fromPrompt(prompt);

    if (intent.dateTime &&
        (config.includeDateTime ||
            config.includeTimezone ||
            config.includeLocale)) {
      return true;
    }

    if (intent.battery && config.includeBattery) return true;
    if (intent.network && config.includeNetwork) return true;
    if (intent.device &&
        (config.includeDeviceInfo ||
            config.includeOsInfo ||
            config.includeAppInfo ||
            config.includeMemory ||
            config.includeStorage ||
            config.includeScreenInfo)) {
      return true;
    }

    if (intent.location && config.includeLocation) return true;

    if (intent.localWeather &&
        config.includeWeather &&
        config.includeLocation) {
      return true;
    }

    if (intent.sensors &&
        (config.includeSensors || config.includeBarometer)) {
      return true;
    }

    return false;
  }

  Future<DeviceContextSnapshot> collect({
    String prompt = '',
  }) async {
    if (!config.enabled) {
      final empty = DeviceContextSnapshot(capturedAt: DateTime.now());
      _lastSnapshot = empty;
      return empty;
    }

    final always = config.mode == DeviceContextMode.always;
    final intent = _DeviceIntent.fromPrompt(prompt);
    final warnings = <String>[];

    final basic = <String, Object?>{};
    final device = <String, Object?>{};
    final app = <String, Object?>{};
    final battery = <String, Object?>{};
    final network = <String, Object?>{};
    final system = <String, Object?>{};
    final screen = <String, Object?>{};
    final location = <String, Object?>{};
    final address = <String, Object?>{};
    final sensors = <String, Object?>{};
    final weather = <String, Object?>{};

    final needBasic = always || intent.dateTime;
    final needDevice = always || intent.device;
    final needBattery = always || intent.battery;
    final needNetwork = always || intent.network || intent.localWeather;
    final needLocation = always || intent.location || intent.localWeather;
    final needSensors = always || intent.sensors;

    if (needBasic) {
      basic.addAll(_collectBasic());
    }

    final futures = <Future<void>>[];

    if (needDevice) {
      if (config.includeDeviceInfo || config.includeOsInfo) {
        futures.add(
          _safeCollect(
            () async => device.addAll(await _collectDevice()),
            warnings,
            'device info',
          ),
        );
      }

      if (config.includeAppInfo) {
        futures.add(
          _safeCollect(
            () async => app.addAll(await _collectApp()),
            warnings,
            'app info',
          ),
        );
      }

      if (config.includeMemory || config.includeStorage) {
        futures.add(
          _safeCollect(
            () async => system.addAll(await _collectSystem()),
            warnings,
            'memory/storage',
          ),
        );
      }

      if (config.includeScreenInfo) {
        futures.add(
          _safeCollect(
            () async => screen.addAll(_collectScreen()),
            warnings,
            'screen info',
          ),
        );
      }
    }

    if (needBattery && config.includeBattery) {
      futures.add(
        _safeCollect(
          () async => battery.addAll(await _collectBattery()),
          warnings,
          'battery',
        ),
      );
    }

    if (needNetwork && config.includeNetwork) {
      futures.add(
        _safeCollect(
          () async => network.addAll(await _collectNetwork()),
          warnings,
          'network',
        ),
      );
    }

    if (needSensors && (config.includeSensors || config.includeBarometer)) {
      futures.add(
        _safeCollect(
          () async => sensors.addAll(await _collectSensors()),
          warnings,
          'sensors',
        ),
      );
    }

    await Future.wait(futures);

    Position? position;

    if (needLocation &&
        (config.includeLocation ||
            config.includeAddress ||
            config.includeWeather ||
            config.includeAltitude ||
            config.includeSpeed ||
            config.includeHeading)) {
      try {
        position = await _getPosition();
      } catch (error) {
        warnings.add('location unavailable: $error');
      }

      if (position != null) {
        if (config.includeLocation ||
            config.includeAltitude ||
            config.includeSpeed ||
            config.includeHeading) {
          location.addAll(_locationMap(position));
        }

        if (config.includeAddress) {
          try {
            address.addAll(
              await _getAddress(position.latitude, position.longitude),
            );
          } catch (error) {
            warnings.add('address unavailable: $error');
          }
        }

        if (config.includeWeather && (always || intent.localWeather)) {
          try {
            weather.addAll(
              await _getWeather(position.latitude, position.longitude),
            );
          } catch (error) {
            warnings.add('weather unavailable: $error');
          }
        }
      }
    }

    final snapshot = DeviceContextSnapshot(
      capturedAt: DateTime.now(),
      basic: basic,
      device: device,
      app: app,
      battery: battery,
      network: network,
      system: system,
      screen: screen,
      location: location,
      address: address,
      sensors: sensors,
      weather: weather,
      warnings: warnings,
    );

    _lastSnapshot = snapshot;
    return snapshot;
  }

  String buildPromptContext(DeviceContextSnapshot snapshot) {
    return snapshot.toPromptContext();
  }

  Map<String, Object?> _collectBasic() {
    final now = DateTime.now();
    final dispatcher = ui.PlatformDispatcher.instance;
    final locale = dispatcher.locale;

    final result = <String, Object?>{};

    if (config.includeDateTime) {
      result['local date'] = _date(now);
      result['local time'] = _time(now);
      result['weekday'] = _weekday(now.weekday);
      result['ISO local datetime'] = now.toIso8601String();
    }

    if (config.includeTimezone) {
      result['timezone name'] = now.timeZoneName;
      result['UTC offset'] = _offsetText(now.timeZoneOffset);
    }

    if (config.includeLocale) {
      result['locale'] = locale.toLanguageTag();
    }

    return result;
  }

  Future<Map<String, Object?>> _collectDevice() async {
    return _cached<Map<String, Object?>>(
      'device',
      config.basicCacheDuration,
      () async {
        final data = <String, Object?>{};

        if (Platform.isAndroid) {
          final info = await _deviceInfo.androidInfo;

          if (config.includeDeviceInfo) {
            data['platform'] = 'Android';
            data['brand'] = info.brand;
            data['manufacturer'] = info.manufacturer;
            data['model'] = info.model;
            data['product'] = info.product;
            data['device'] = info.device;
            data['physical device'] = info.isPhysicalDevice;
          }

          if (config.includeOsInfo) {
            data['Android release'] = info.version.release;
            data['Android SDK'] = info.version.sdkInt;
          }
        } else if (Platform.isIOS) {
          final info = await _deviceInfo.iosInfo;

          if (config.includeDeviceInfo) {
            data['platform'] = 'iOS';
            data['device name'] = info.name;
            data['model'] = info.model;
            data['hardware'] = info.utsname.machine;
            data['physical device'] = info.isPhysicalDevice;
          }

          if (config.includeOsInfo) {
            data['system name'] = info.systemName;
            data['system version'] = info.systemVersion;
          }
        } else {
          if (config.includeDeviceInfo) {
            data['platform'] = Platform.operatingSystem;
          }
          if (config.includeOsInfo) {
            data['OS version'] = Platform.operatingSystemVersion;
          }
        }

        return data;
      },
    );
  }

  Future<Map<String, Object?>> _collectApp() {
    return _cached<Map<String, Object?>>(
      'app',
      config.basicCacheDuration,
      () async {
        final info = await PackageInfo.fromPlatform();

        return <String, Object?>{
          'app name': info.appName,
          'package name': info.packageName,
          'version': info.version,
          'build number': info.buildNumber,
        };
      },
    );
  }

  Future<Map<String, Object?>> _collectBattery() async {
    final level = await _battery.batteryLevel;
    final state = await _battery.batteryState;

    bool? saver;
    try {
      saver = await _battery.isInBatterySaveMode;
    } catch (_) {}

    return <String, Object?>{
      'level percent': level,
      'state': state.name,
      // Keep explicit conditional syntax for compatibility/readability.
      // ignore: use_null_aware_elements
      if (saver != null) 'battery saver': saver,
    };
  }

  Future<Map<String, Object?>> _collectNetwork() async {
    final results = await _connectivity.checkConnectivity();
    final types = results.map((value) => value.name).toSet().toList();

    final connected =
        types.isNotEmpty && !types.every((value) => value == 'none');

    return <String, Object?>{
      'connected transport available': connected,
      'connection types': types.join(', '),
    };
  }

  Future<Map<String, Object?>> _collectSystem() {
    return _cached<Map<String, Object?>>(
      'system',
      config.basicCacheDuration,
      () async {
        const mb = 1024 * 1024;
        const gb = 1024 * 1024 * 1024;

        final values = <String, Object?>{};

        if (config.includeMemory) {
          try {
            values['total RAM MB'] =
                (SysInfo.getTotalPhysicalMemory() / mb).round();
            values['available RAM MB'] =
                (SysInfo.getAvailablePhysicalMemory() / mb).round();
          } catch (_) {
            try {
              values['free RAM MB'] =
                  (SysInfo.getFreePhysicalMemory() / mb).round();
              values['total RAM MB'] =
                  (SysInfo.getTotalPhysicalMemory() / mb).round();
            } catch (_) {}
          }
        }

        if (config.includeStorage) {
          try {
            values['total storage GB'] =
                (SysInfo.getTotalStorage() / gb).toStringAsFixed(2);
            values['free storage GB'] =
                (SysInfo.getFreeStorage() / gb).toStringAsFixed(2);
          } catch (_) {}
        }

        return values;
      },
    );
  }

  Map<String, Object?> _collectScreen() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return const <String, Object?>{};

    final view = views.first;
    final dpr = view.devicePixelRatio;
    final physical = view.physicalSize;
    final logicalWidth = dpr == 0 ? physical.width : physical.width / dpr;
    final logicalHeight = dpr == 0 ? physical.height : physical.height / dpr;

    return <String, Object?>{
      'physical width px': physical.width.round(),
      'physical height px': physical.height.round(),
      'device pixel ratio': dpr.toStringAsFixed(2),
      'logical width': logicalWidth.toStringAsFixed(1),
      'logical height': logicalHeight.toStringAsFixed(1),
      'orientation':
          logicalWidth >= logicalHeight ? 'landscape' : 'portrait',
    };
  }

  Future<Position?> _getPosition() {
    return _cached<Position?>(
      'location',
      config.locationCacheDuration,
      () async {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw StateError('location service is disabled');
        }

        var permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied &&
            config.requestLocationPermissionWhenNeeded) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied) {
          throw StateError(
            'location permission is denied; request it from the host app',
          );
        }

        if (permission == LocationPermission.deniedForever) {
          throw StateError('location permission is permanently denied');
        }

        return Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: config.locationTimeout,
          ),
        );
      },
    );
  }

  Map<String, Object?> _locationMap(Position position) {
    final values = <String, Object?>{};

    if (config.includeLocation) {
      values['latitude'] = position.latitude;
      values['longitude'] = position.longitude;
      values['accuracy meters'] = position.accuracy;
      values['location timestamp'] = position.timestamp.toIso8601String();
    }

    if (config.includeAltitude) {
      values['altitude meters'] = position.altitude;
    }

    if (config.includeSpeed) {
      values['speed m/s'] = position.speed;
    }

    if (config.includeHeading) {
      values['heading degrees'] = position.heading;
    }

    return values;
  }

  Future<Map<String, Object?>> _getAddress(
    double latitude,
    double longitude,
  ) {
    final key =
        'address:${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';

    return _cached<Map<String, Object?>>(
      key,
      config.locationCacheDuration,
      () async {
        final placemarks = await _geocoding.placemarkFromCoordinates(
          latitude,
          longitude,
        );

        if (placemarks.isEmpty) {
          return const <String, Object?>{};
        }

        final place = placemarks.first;

        final full = <String?>[
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ]
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .join(', ');

        return <String, Object?>{
          if ((place.locality ?? '').trim().isNotEmpty)
            'city/locality': place.locality,
          if ((place.subAdministrativeArea ?? '').trim().isNotEmpty)
            'sub-administrative area': place.subAdministrativeArea,
          if ((place.administrativeArea ?? '').trim().isNotEmpty)
            'administrative area': place.administrativeArea,
          if ((place.country ?? '').trim().isNotEmpty)
            'country': place.country,
          if ((place.isoCountryCode ?? '').trim().isNotEmpty)
            'country code': place.isoCountryCode,
          if (full.isNotEmpty) 'address': full,
        };
      },
    );
  }

  Future<Map<String, Object?>> _collectSensors() async {
    final values = <String, Object?>{};

    if (config.includeSensors) {
      try {
        final event = await accelerometerEventStream()
            .first
            .timeout(config.sensorTimeout);
        values['accelerometer m/s²'] =
            'x=${event.x.toStringAsFixed(3)}, '
            'y=${event.y.toStringAsFixed(3)}, '
            'z=${event.z.toStringAsFixed(3)}';
      } catch (_) {}

      try {
        final event = await gyroscopeEventStream()
            .first
            .timeout(config.sensorTimeout);
        values['gyroscope rad/s'] =
            'x=${event.x.toStringAsFixed(3)}, '
            'y=${event.y.toStringAsFixed(3)}, '
            'z=${event.z.toStringAsFixed(3)}';
      } catch (_) {}

      try {
        final event = await magnetometerEventStream()
            .first
            .timeout(config.sensorTimeout);
        values['magnetometer µT'] =
            'x=${event.x.toStringAsFixed(3)}, '
            'y=${event.y.toStringAsFixed(3)}, '
            'z=${event.z.toStringAsFixed(3)}';
      } catch (_) {}
    }

    if (config.includeBarometer) {
      try {
        final event = await barometerEventStream()
            .first
            .timeout(config.sensorTimeout);
        values['barometric pressure hPa'] =
            event.pressure.toStringAsFixed(2);
      } catch (_) {}
    }

    return values;
  }

  Future<Map<String, Object?>> _getWeather(
    double latitude,
    double longitude,
  ) {
    final key =
        'weather:${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';

    return _cached<Map<String, Object?>>(
      key,
      config.weatherCacheDuration,
      () async {
        final uri = Uri.https(
          'api.open-meteo.com',
          '/v1/forecast',
          <String, String>{
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            'current': [
              'temperature_2m',
              'relative_humidity_2m',
              'apparent_temperature',
              'precipitation',
              'rain',
              'weather_code',
              'cloud_cover',
              'surface_pressure',
              'wind_speed_10m',
              'wind_direction_10m',
            ].join(','),
            'timezone': 'auto',
          },
        );

        final client = HttpClient()
          ..connectionTimeout = config.weatherTimeout;

        try {
          final request =
              await client.getUrl(uri).timeout(config.weatherTimeout);
          request.headers.set(
            HttpHeaders.acceptHeader,
            'application/json',
          );

          final response =
              await request.close().timeout(config.weatherTimeout);

          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException(
              'weather HTTP ${response.statusCode}',
              uri: uri,
            );
          }

          final body = await response
              .transform(const Utf8Decoder(allowMalformed: true))
              .join()
              .timeout(config.weatherTimeout);

          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('invalid weather response');
          }

          final current = decoded['current'];
          if (current is! Map) {
            return const <String, Object?>{};
          }

          final data = Map<String, dynamic>.from(current);
          final weatherCode =
              int.tryParse(data['weather_code']?.toString() ?? '');

          return <String, Object?>{
            if (data['time'] != null) 'observation time': data['time'],
            if (data['temperature_2m'] != null)
              'temperature °C': data['temperature_2m'],
            if (data['apparent_temperature'] != null)
              'feels like °C': data['apparent_temperature'],
            if (data['relative_humidity_2m'] != null)
              'relative humidity %': data['relative_humidity_2m'],
            if (data['precipitation'] != null)
              'precipitation mm': data['precipitation'],
            if (data['rain'] != null) 'rain mm': data['rain'],
            if (data['cloud_cover'] != null)
              'cloud cover %': data['cloud_cover'],
            if (data['surface_pressure'] != null)
              'surface pressure hPa': data['surface_pressure'],
            if (data['wind_speed_10m'] != null)
              'wind speed km/h': data['wind_speed_10m'],
            if (data['wind_direction_10m'] != null)
              'wind direction degrees': data['wind_direction_10m'],
            if (weatherCode != null) 'weather code': weatherCode,
            // ignore: use_null_aware_elements
            if (weatherCode != null)
              'condition': _weatherDescription(weatherCode),
            if (decoded['timezone'] != null)
              'weather timezone': decoded['timezone'],
          };
        } finally {
          client.close(force: true);
        }
      },
    );
  }

  Future<void> _safeCollect(
    Future<void> Function() action,
    List<String> warnings,
    String label,
  ) async {
    try {
      await action();
    } catch (error) {
      warnings.add('$label unavailable: $error');
    }
  }

  Future<T> _cached<T>(
    String key,
    Duration maxAge,
    Future<T> Function() loader,
  ) async {
    final now = DateTime.now();
    final cached = _cache[key];

    if (cached != null && now.difference(cached.savedAt) <= maxAge) {
      return cached.value as T;
    }

    final value = await loader();
    _cache[key] = _CacheEntry<Object?>(
      savedAt: now,
      value: value,
    );
    return value;
  }

  static String _date(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _offsetText(Duration offset) {
    final negative = offset.isNegative;
    final totalMinutes = offset.inMinutes.abs();
    final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
    return 'UTC${negative ? '-' : '+'}$hours:$minutes';
  }

  static String _weekday(int weekday) {
    const names = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final index = (weekday - 1).clamp(0, 6).toInt();
    return names[index];
  }

  static String _weatherDescription(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
        return 'Rain';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Unknown';
    }
  }
}

class _CacheEntry<T> {
  const _CacheEntry({
    required this.savedAt,
    required this.value,
  });

  final DateTime savedAt;
  final T value;
}

class _DeviceIntent {
  const _DeviceIntent({
    required this.dateTime,
    required this.device,
    required this.battery,
    required this.network,
    required this.location,
    required this.weather,
    required this.localWeather,
    required this.sensors,
  });

  final bool dateTime;
  final bool device;
  final bool battery;
  final bool network;
  final bool location;
  final bool weather;
  final bool localWeather;
  final bool sensors;

  factory _DeviceIntent.fromPrompt(String prompt) {
    final value = prompt.toLowerCase();

    bool any(List<String> terms) => terms.any(value.contains);

    final weather = any(const <String>[
      'weather',
      'temperature',
      'humidity',
      'rain',
      'raining',
      'forecast',
      'wind',
      'আবহাওয়া',
      'আবহাওয়া',
      'তাপমাত্রা',
      'বৃষ্টি',
      'brishti',
      'abohawa',
      'weather kemon',
    ]);

    final localWeather = weather && any(const <String>[
      'weather here',
      'weather at my location',
      'weather around me',
      'weather kemon',
      'abohawa kemon',
      'amar ekhane',
      'ekhankar weather',
      'ekhane weather',
      'এখানকার আবহাওয়া',
      'এখানকার আবহাওয়া',
      'এখানে আবহাওয়া',
      'এখানে আবহাওয়া',
    ]);

    final location = localWeather ||
        any(const <String>[
          'my location',
          'current location',
          'where am i',
          'where i am',
          'latitude',
          'longitude',
          'altitude',
          'elevation',
          'gps',
          'my address',
          'current address',
          'which city',
          'what city',
          'my city',
          'speed',
          'heading',
          'direction am i',
          'ami kothay',
          'amar location',
          'amar address',
          'amar altitude',
          'amar speed',
          'আমি কোথায়',
          'আমি কোথায়',
          'আমার লোকেশন',
          'আমার অবস্থান',
          'অক্ষাংশ',
          'দ্রাঘিমাংশ',
          'উচ্চতা',
        ]);

    return _DeviceIntent(
      dateTime: any(const <String>[
        'what time',
        'current time',
        'time now',
        'date today',
        'today date',
        'current date',
        'timezone',
        'time zone',
        'what day',
        'which day',
        'koyta baje',
        'koita baje',
        'date koto',
        'ajke date',
        'aj ki bar',
        'আজ কত তারিখ',
        'এখন কয়টা',
        'এখন কয়টা',
        'কয়টা বাজে',
        'কয়টা বাজে',
        'আজ কী বার',
        'আজ কি বার',
        'টাইমজোন',
      ]),
      device: any(const <String>[
        'my phone',
        'my device',
        'device model',
        'phone model',
        'android version',
        'ios version',
        'os version',
        'app version',
        'build number',
        'screen size',
        'resolution',
        'ram',
        'memory',
        'storage',
        'free space',
        'amar phone',
        'amar device',
        'phone model ki',
        'ram koto',
        'storage koto',
        'ফোন মডেল',
        'ডিভাইস',
        'র‍্যাম',
        'র‌্যাম',
        'স্টোরেজ',
      ]),
      battery: any(const <String>[
        'battery',
        'charging',
        'charge level',
        'power saver',
        'battery saver',
        'battery koto',
        'charge koto',
        'চার্জ',
        'ব্যাটারি',
      ]),
      network: any(const <String>[
        'internet',
        'network',
        'wifi',
        'wi-fi',
        'mobile data',
        'cellular',
        'offline',
        'online',
        'internet ase',
        'net ase',
        'ইন্টারনেট',
        'নেটওয়ার্ক',
        'নেটওয়ার্ক',
        'ওয়াইফাই',
        'ওয়াইফাই',
      ]),
      location: location,
      weather: weather,
      localWeather: localWeather,
      sensors: any(const <String>[
        'accelerometer',
        'gyroscope',
        'magnetometer',
        'compass',
        'barometer',
        'pressure sensor',
        'motion sensor',
        'tilt',
        'orientation sensor',
        'কম্পাস',
        'ব্যারোমিটার',
        'সেন্সর',
      ]),
    );
  }
}
