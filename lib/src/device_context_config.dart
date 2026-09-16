enum DeviceContextMode {
  auto,
  always,
}

class DeviceContextConfig {
  const DeviceContextConfig({
    this.enabled = false,
    this.mode = DeviceContextMode.auto,
    this.includeDateTime = true,
    this.includeTimezone = true,
    this.includeLocale = true,
    this.includeDeviceInfo = true,
    this.includeOsInfo = true,
    this.includeAppInfo = true,
    this.includeBattery = true,
    this.includeNetwork = true,
    this.includeStorage = true,
    this.includeMemory = true,
    this.includeScreenInfo = true,
    this.includeLocation = true,
    this.includeAddress = true,
    this.includeAltitude = true,
    this.includeSpeed = true,
    this.includeHeading = true,
    this.includeSensors = false,
    this.includeBarometer = false,
    this.includeWeather = true,
    this.requestLocationPermissionWhenNeeded = false,
    this.basicCacheDuration = const Duration(minutes: 5),
    this.locationCacheDuration = const Duration(minutes: 2),
    this.weatherCacheDuration = const Duration(minutes: 15),
    this.sensorTimeout = const Duration(seconds: 2),
    this.locationTimeout = const Duration(seconds: 10),
    this.weatherTimeout = const Duration(seconds: 8),
  });

  /// Master switch. No device context is collected when false.
  final bool enabled;

  /// auto = collect only context relevant to the current prompt.
  /// always = collect every enabled category for every generation.
  final DeviceContextMode mode;

  final bool includeDateTime;
  final bool includeTimezone;
  final bool includeLocale;

  final bool includeDeviceInfo;
  final bool includeOsInfo;
  final bool includeAppInfo;

  final bool includeBattery;
  final bool includeNetwork;
  final bool includeStorage;
  final bool includeMemory;
  final bool includeScreenInfo;

  final bool includeLocation;
  final bool includeAddress;
  final bool includeAltitude;
  final bool includeSpeed;
  final bool includeHeading;

  final bool includeSensors;
  final bool includeBarometer;

  /// Current weather is fetched from Open-Meteo using the current location.
  /// No API key is required.
  final bool includeWeather;

  /// false by default so a package never surprises the user with a permission
  /// dialog. The host app can explicitly call requestDeviceLocationPermission().
  final bool requestLocationPermissionWhenNeeded;

  final Duration basicCacheDuration;
  final Duration locationCacheDuration;
  final Duration weatherCacheDuration;
  final Duration sensorTimeout;
  final Duration locationTimeout;
  final Duration weatherTimeout;

  DeviceContextConfig copyWith({
    bool? enabled,
    DeviceContextMode? mode,
    bool? includeDateTime,
    bool? includeTimezone,
    bool? includeLocale,
    bool? includeDeviceInfo,
    bool? includeOsInfo,
    bool? includeAppInfo,
    bool? includeBattery,
    bool? includeNetwork,
    bool? includeStorage,
    bool? includeMemory,
    bool? includeScreenInfo,
    bool? includeLocation,
    bool? includeAddress,
    bool? includeAltitude,
    bool? includeSpeed,
    bool? includeHeading,
    bool? includeSensors,
    bool? includeBarometer,
    bool? includeWeather,
    bool? requestLocationPermissionWhenNeeded,
    Duration? basicCacheDuration,
    Duration? locationCacheDuration,
    Duration? weatherCacheDuration,
    Duration? sensorTimeout,
    Duration? locationTimeout,
    Duration? weatherTimeout,
  }) {
    return DeviceContextConfig(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      includeDateTime: includeDateTime ?? this.includeDateTime,
      includeTimezone: includeTimezone ?? this.includeTimezone,
      includeLocale: includeLocale ?? this.includeLocale,
      includeDeviceInfo: includeDeviceInfo ?? this.includeDeviceInfo,
      includeOsInfo: includeOsInfo ?? this.includeOsInfo,
      includeAppInfo: includeAppInfo ?? this.includeAppInfo,
      includeBattery: includeBattery ?? this.includeBattery,
      includeNetwork: includeNetwork ?? this.includeNetwork,
      includeStorage: includeStorage ?? this.includeStorage,
      includeMemory: includeMemory ?? this.includeMemory,
      includeScreenInfo: includeScreenInfo ?? this.includeScreenInfo,
      includeLocation: includeLocation ?? this.includeLocation,
      includeAddress: includeAddress ?? this.includeAddress,
      includeAltitude: includeAltitude ?? this.includeAltitude,
      includeSpeed: includeSpeed ?? this.includeSpeed,
      includeHeading: includeHeading ?? this.includeHeading,
      includeSensors: includeSensors ?? this.includeSensors,
      includeBarometer: includeBarometer ?? this.includeBarometer,
      includeWeather: includeWeather ?? this.includeWeather,
      requestLocationPermissionWhenNeeded:
          requestLocationPermissionWhenNeeded ??
              this.requestLocationPermissionWhenNeeded,
      basicCacheDuration: basicCacheDuration ?? this.basicCacheDuration,
      locationCacheDuration:
          locationCacheDuration ?? this.locationCacheDuration,
      weatherCacheDuration: weatherCacheDuration ?? this.weatherCacheDuration,
      sensorTimeout: sensorTimeout ?? this.sensorTimeout,
      locationTimeout: locationTimeout ?? this.locationTimeout,
      weatherTimeout: weatherTimeout ?? this.weatherTimeout,
    );
  }
}
