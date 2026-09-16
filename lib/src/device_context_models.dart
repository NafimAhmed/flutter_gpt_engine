class DeviceContextSnapshot {
  const DeviceContextSnapshot({
    required this.capturedAt,
    this.basic = const <String, Object?>{},
    this.device = const <String, Object?>{},
    this.app = const <String, Object?>{},
    this.battery = const <String, Object?>{},
    this.network = const <String, Object?>{},
    this.system = const <String, Object?>{},
    this.screen = const <String, Object?>{},
    this.location = const <String, Object?>{},
    this.address = const <String, Object?>{},
    this.sensors = const <String, Object?>{},
    this.weather = const <String, Object?>{},
    this.warnings = const <String>[],
  });

  final DateTime capturedAt;

  final Map<String, Object?> basic;
  final Map<String, Object?> device;
  final Map<String, Object?> app;
  final Map<String, Object?> battery;
  final Map<String, Object?> network;
  final Map<String, Object?> system;
  final Map<String, Object?> screen;
  final Map<String, Object?> location;
  final Map<String, Object?> address;
  final Map<String, Object?> sensors;
  final Map<String, Object?> weather;

  /// Collection failures/permission notes for the host app. They are not
  /// automatically injected into the LLM prompt.
  final List<String> warnings;

  bool get isEmpty =>
      basic.isEmpty &&
      device.isEmpty &&
      app.isEmpty &&
      battery.isEmpty &&
      network.isEmpty &&
      system.isEmpty &&
      screen.isEmpty &&
      location.isEmpty &&
      address.isEmpty &&
      sensors.isEmpty &&
      weather.isEmpty;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'capturedAt': capturedAt.toIso8601String(),
      if (basic.isNotEmpty) 'basic': basic,
      if (device.isNotEmpty) 'device': device,
      if (app.isNotEmpty) 'app': app,
      if (battery.isNotEmpty) 'battery': battery,
      if (network.isNotEmpty) 'network': network,
      if (system.isNotEmpty) 'system': system,
      if (screen.isNotEmpty) 'screen': screen,
      if (location.isNotEmpty) 'location': location,
      if (address.isNotEmpty) 'address': address,
      if (sensors.isNotEmpty) 'sensors': sensors,
      if (weather.isNotEmpty) 'weather': weather,
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }

  String toPromptContext() {
    if (isEmpty && warnings.isEmpty) return '';

    final buffer = StringBuffer()
      ..writeln('DEVICE CONTEXT (trusted local/app-provided data):')
      ..writeln(
        'Use this data only when relevant. Never invent missing device values.',
      );

    void writeGroup(String title, Map<String, Object?> values) {
      if (values.isEmpty) return;
      buffer.writeln();
      buffer.writeln('$title:');
      for (final entry in values.entries) {
        final value = entry.value;
        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        buffer.writeln('- ${entry.key}: $value');
      }
    }

    writeGroup('DATE / TIME / LOCALE', basic);
    writeGroup('DEVICE / OS', device);
    writeGroup('APP', app);
    writeGroup('BATTERY', battery);
    writeGroup('NETWORK', network);
    writeGroup('MEMORY / STORAGE', system);
    writeGroup('SCREEN', screen);
    writeGroup('LOCATION', location);
    writeGroup('ADDRESS', address);
    writeGroup('SENSORS', sensors);
    writeGroup('CURRENT WEATHER', weather);

    if (warnings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('UNAVAILABLE DEVICE CONTEXT:');
      for (final warning in warnings) {
        final clean = warning.trim();
        if (clean.isNotEmpty) buffer.writeln('- $clean');
      }
      buffer.writeln(
        'Do not guess unavailable location, weather, sensor, or device values.',
      );
    }

    return buffer.toString().trim();
  }
}
