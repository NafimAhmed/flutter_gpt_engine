import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

import 'local_llm_config.dart';
import 'local_llm_message.dart';
import 'local_llm_model.dart';

class LocalLlmClient extends ChangeNotifier {
  LocalLlmClient({
    this.config = const LocalLlmConfig(),
  });

  final LocalLlmConfig config;

  LlamaController _llama = LlamaController();

  final List<LocalLlmMessage> _messages = <LocalLlmMessage>[];

  bool _isLoading = false;
  bool _isLoaded = false;
  bool _isGenerating = false;
  bool _disposed = false;

  String _status = 'No model loaded';
  LocalLlmModel? _model;

  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;
  bool get isGenerating => _isGenerating;
  String get status => _status;
  LocalLlmModel? get model => _model;

  List<LocalLlmMessage> get messages =>
      List.unmodifiable(_messages.map((message) => message.copy()));

  /// Opens the native File Picker and lets the user select a .gguf file.
  ///
  /// If [persist] is true, the selected model is copied into this app's
  /// Application Support directory before it is loaded. This is useful when
  /// the picker returns a temporary/cache-backed path.
  Future<bool> pickModel({
    bool persist = false,
  }) async {
    _ensureNotDisposed();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return false;
    }

    final picked = result.files.single;
    final pickedPath = picked.path;

    if (pickedPath == null || pickedPath.trim().isEmpty) {
      throw StateError(
        'The selected GGUF file did not provide a readable filesystem path.',
      );
    }

    var pathToLoad = pickedPath;

    if (persist) {
      pathToLoad = await _copyFileToAppSupport(
        sourcePath: pickedPath,
        preferredName: picked.name,
      );
    }

    await loadModel(
      pathToLoad,
      source: LocalLlmModelSource.pickedFile,
      displayName: picked.name,
    );

    return true;
  }

  /// Loads an existing .gguf model from a filesystem path.
  Future<void> loadModel(
    String modelPath, {
    LocalLlmModelSource source = LocalLlmModelSource.filePath,
    String? displayName,
  }) async {
    _ensureNotDisposed();

    if (_isLoading) {
      throw StateError('A model is already being loaded.');
    }

    final file = File(modelPath);
    await _validateGgufFile(file);

    _isLoading = true;
    _isLoaded = false;
    _status = 'Preparing model...';
    _safeNotify();

    try {
      await stop();
      await _disposeController();
      _llama = LlamaController();

      int requestedGpuLayers;

      if (config.gpuLayers != null) {
        requestedGpuLayers = config.gpuLayers!;
      } else {
        final gpu = await _llama.detectGpu();
        requestedGpuLayers = gpu.recommendedGpuLayers;
      }

      _status = requestedGpuLayers > 0
          ? 'Loading model with GPU acceleration...'
          : 'Loading model on CPU...';
      _safeNotify();

      try {
        await _llama.loadModel(
          modelPath: modelPath,
          threads: config.threads,
          contextSize: config.contextSize,
          gpuLayers: requestedGpuLayers,
        );
      } catch (gpuError) {
        if (requestedGpuLayers <= 0) {
          rethrow;
        }

        debugPrint(
          'Flutter_GPT_Engine: GPU model load failed. Retrying on CPU. '
          'Error: $gpuError',
        );

        _status = 'GPU load failed. Retrying on CPU...';
        _safeNotify();

        await _disposeController();
        _llama = LlamaController();

        await _llama.loadModel(
          modelPath: modelPath,
          threads: config.threads,
          contextSize: config.contextSize,
          gpuLayers: 0,
        );
      }

      _model = LocalLlmModel(
        path: modelPath,
        name: displayName ?? _fileName(modelPath),
        source: source,
      );

      _isLoaded = true;
      _status = 'Ready';
    } catch (error) {
      _model = null;
      _isLoaded = false;
      _status = 'Model load failed: $error';

      await _disposeController();
      _llama = LlamaController();

      rethrow;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Loads a GGUF model declared in the host application's Flutter assets.
  ///
  /// Example host app pubspec:
  ///
  /// flutter:
  ///   assets:
  ///     - assets/models/qwen.gguf
  ///
  /// Flutter assets are not normal filesystem paths, so the package copies
  /// the asset to Application Support and then loads that copied file.
  Future<void> loadAsset(
    String assetPath, {
    bool overwriteCachedCopy = false,
  }) async {
    _ensureNotDisposed();

    final assetName = _fileName(assetPath);

    if (!assetName.toLowerCase().endsWith('.gguf')) {
      throw ArgumentError.value(
        assetPath,
        'assetPath',
        'The asset must be a .gguf file.',
      );
    }

    final directory = await _modelDirectory();
    final output = File(
      '${directory.path}${Platform.pathSeparator}$assetName',
    );

    if (overwriteCachedCopy && await output.exists()) {
      await output.delete();
    }

    if (!await output.exists()) {
      _status = 'Copying model asset to local storage...';
      _isLoading = true;
      _safeNotify();

      try {
        final data = await rootBundle.load(assetPath);
        await output.writeAsBytes(
          data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
          flush: true,
        );
      } finally {
        _isLoading = false;
        _safeNotify();
      }
    }

    await loadModel(
      output.path,
      source: LocalLlmModelSource.asset,
      displayName: assetName,
    );
  }

  /// Sends [prompt] using the current local model and streams generated tokens.
  ///
  /// The user message and streaming assistant message are automatically kept
  /// in [messages].
  Stream<String> generate(
    String prompt, {
    String? systemPrompt,
  }) async* {
    _ensureNotDisposed();

    final cleanPrompt = prompt.trim();

    if (cleanPrompt.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'Prompt cannot be empty.');
    }

    if (!_isLoaded) {
      throw StateError('Load a GGUF model before generating.');
    }

    if (_isGenerating) {
      throw StateError('A generation is already running.');
    }

    final previous = _historyForPrompt();

    final userMessage = LocalLlmMessage(
      role: 'user',
      text: cleanPrompt,
    );

    final assistantMessage = LocalLlmMessage(
      role: 'assistant',
      text: '',
    );

    _messages.add(userMessage);
    _messages.add(assistantMessage);

    _isGenerating = true;
    _status = 'Generating...';
    _safeNotify();

    final chatMessages = <ChatMessage>[
      ChatMessage(
        role: 'system',
        content: systemPrompt ?? config.systemPrompt,
      ),
      ...previous.map(
        (message) => ChatMessage(
          role: message.role,
          content: message.text,
        ),
      ),
      ChatMessage(
        role: 'user',
        content: cleanPrompt,
      ),
    ];

    try {
      await _llama.clearContext();

      final stream = _llama.generateChat(
        messages: chatMessages,
        temperature: config.temperature,
        topP: config.topP,
        topK: config.topK,
        repeatPenalty: config.repeatPenalty,
        maxTokens: config.maxTokens,
      );

      await for (final token in stream) {
        assistantMessage.text += token;
        _safeNotify();
        yield token;
      }

      _status = 'Ready';
    } catch (error) {
      if (assistantMessage.text.trim().isEmpty) {
        _messages.remove(assistantMessage);
      }

      _status = 'Generation error: $error';
      rethrow;
    } finally {
      _isGenerating = false;
      _safeNotify();
    }
  }

  /// Convenience helper for callers that prefer a full String instead of
  /// consuming the token stream themselves.
  Future<String> generateText(
    String prompt, {
    String? systemPrompt,
  }) async {
    final buffer = StringBuffer();

    await for (final token in generate(
      prompt,
      systemPrompt: systemPrompt,
    )) {
      buffer.write(token);
    }

    return buffer.toString();
  }

  Future<void> stop() async {
    if (_disposed) return;

    try {
      await _llama.stop();
    } catch (_) {
      // Native stop can legitimately fail when no generation is active.
    }

    if (_isGenerating) {
      _isGenerating = false;
      _status = _isLoaded ? 'Ready' : _status;
      _safeNotify();
    }
  }

  Future<void> clearChat() async {
    _ensureNotDisposed();

    await stop();

    if (_isLoaded) {
      try {
        await _llama.clearContext();
      } catch (_) {}
    }

    _messages.clear();
    _status = _isLoaded ? 'Ready' : 'No model loaded';
    _safeNotify();
  }

  Future<void> unloadModel() async {
    _ensureNotDisposed();

    await stop();
    await _disposeController();
    _llama = LlamaController();

    _model = null;
    _isLoaded = false;
    _isLoading = false;
    _status = 'No model loaded';
    _safeNotify();
  }

  List<LocalLlmMessage> _historyForPrompt() {
    if (_messages.isEmpty || config.maxHistoryMessages <= 0) {
      return const <LocalLlmMessage>[];
    }

    // The current user/assistant pair has not been appended yet when this
    // method is called.
    final int start =
        _messages.length > config.maxHistoryMessages
            ? _messages.length - config.maxHistoryMessages
            : 0;

    return _messages
        .sublist(start)
        .where(
          (message) =>
              message.text.trim().isNotEmpty &&
              (message.role == 'user' || message.role == 'assistant'),
        )
        .map((message) => message.copy())
        .toList();
  }

  Future<void> _validateGgufFile(File file) async {
    if (!await file.exists()) {
      throw FileSystemException(
        'GGUF model file does not exist.',
        file.path,
      );
    }

    if (!file.path.toLowerCase().endsWith('.gguf')) {
      throw ArgumentError.value(
        file.path,
        'modelPath',
        'Model file must use the .gguf extension.',
      );
    }

    if (await file.length() < 4) {
      throw const FormatException('GGUF model file is empty or incomplete.');
    }

    final handle = await file.open(mode: FileMode.read);

    try {
      final header = await handle.read(4);
      final magic = String.fromCharCodes(header);

      if (magic != 'GGUF') {
        throw const FormatException(
          'Selected file is not a valid GGUF model.',
        );
      }
    } finally {
      await handle.close();
    }
  }

  Future<Directory> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}flutter_gpt_engine_models',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<String> _copyFileToAppSupport({
    required String sourcePath,
    required String preferredName,
  }) async {
    final source = File(sourcePath);
    await _validateGgufFile(source);

    final directory = await _modelDirectory();

    final safeName = preferredName.toLowerCase().endsWith('.gguf')
        ? preferredName
        : '${_fileName(sourcePath)}.gguf';

    final destination = File(
      '${directory.path}${Platform.pathSeparator}$safeName',
    );

    if (source.absolute.path == destination.absolute.path) {
      return destination.path;
    }

    if (await destination.exists()) {
      final sourceLength = await source.length();
      final destinationLength = await destination.length();

      if (sourceLength == destinationLength) {
        await _validateGgufFile(destination);
        return destination.path;
      }

      await destination.delete();
    }

    await source.copy(destination.path);
    await _validateGgufFile(destination);

    return destination.path;
  }

  Future<void> _disposeController() async {
    try {
      await _llama.dispose();
    } catch (_) {}
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('LocalLlmClient has already been disposed.');
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;

    // ChangeNotifier.dispose() cannot await native cleanup.
    // Fire-and-forget is intentional here; callers that need deterministic
    // cleanup should call unloadModel() before dispose().
    unawaited(_disposeController());

    super.dispose();
  }
}
