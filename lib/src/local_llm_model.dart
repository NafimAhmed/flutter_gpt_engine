enum LocalLlmModelSource {
  pickedFile,
  filePath,
  asset,
}

class LocalLlmModel {
  const LocalLlmModel({
    required this.path,
    required this.name,
    required this.source,
  });

  /// Real filesystem path that llama.cpp can load.
  final String path;
  final String name;
  final LocalLlmModelSource source;

  @override
  String toString() => 'LocalLlmModel(name: $name, path: $path, source: $source)';
}
