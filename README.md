# Flutter_GPT_Engine

`Flutter_GPT_Engine` is a **headless local GGUF chat engine for Flutter**.

It does **not** provide any chat screen, bubble, text field, app bar, theme, or other UI.

The host app owns 100% of the UI.

The package handles:

- GGUF model selection using File Picker
- Flutter asset model loading
- direct filesystem-path model loading
- GGUF validation
- GPU detection
- GPU -> CPU fallback
- model lifecycle
- streaming generation
- conversation history
- stop generation
- clear chat
- unload/dispose
- generation configuration

## Package name

```yaml
name: flutter_gpt_engine
```

Import:

```dart
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';
```

## 1. Create the client

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    systemPrompt: 'You are a helpful offline AI assistant.',
    threads: 4,
    contextSize: 4096,
    maxTokens: 384,
  ),
);
```

## 2. User selects a GGUF model using File Picker

Your UI can have any button you want. On tap:

```dart
final selected = await gpt.pickModel();

if (selected) {
  print(gpt.model?.name);
}
```

If you want the picked model copied into Application Support:

```dart
await gpt.pickModel(
  persist: true,
);
```

## 3. Load from Flutter assets

Host app `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/qwen.gguf
```

Then:

```dart
await gpt.loadAsset(
  'assets/models/qwen.gguf',
);
```

## 4. Load from direct file path

```dart
await gpt.loadModel(
  '/storage/emulated/0/Download/model.gguf',
);
```

## 5. Stream chat response

```dart
await for (final token in gpt.generate('Hello')) {
  // Show this token however you want in your own UI.
  print(token);
}
```

Or get the complete answer:

```dart
final answer = await gpt.generateText(
  'Explain Flutter in Bangla.',
);
```

## 6. Observe package state

`LocalLlmClient` extends `ChangeNotifier`.

Your UI can listen to it:

```dart
gpt.addListener(() {
  print(gpt.isLoading);
  print(gpt.isLoaded);
  print(gpt.isGenerating);
  print(gpt.status);
  print(gpt.model);
  print(gpt.messages);
});
```

Available state:

```dart
gpt.isLoading
gpt.isLoaded
gpt.isGenerating
gpt.status
gpt.model
gpt.messages
```

## 7. Conversation history

The package automatically keeps user/assistant messages:

```dart
final messages = gpt.messages;

for (final message in messages) {
  print('${message.role}: ${message.text}');
}
```

Your UI can render these messages however it wants.

## 8. Stop / clear / unload

```dart
await gpt.stop();
```

```dart
await gpt.clearChat();
```

```dart
await gpt.unloadModel();
```

## 9. Dispose

```dart
gpt.dispose();
```

If deterministic native cleanup is needed before destroying the object:

```dart
await gpt.unloadModel();
gpt.dispose();
```

## Architecture

```text
YOUR APP UI
   |
   |-- Pick Model button
   |-- TextField
   |-- Send button
   |-- Chat bubbles
   |
   v
Flutter_GPT_Engine
   |
   |-- File Picker
   |-- GGUF validation
   |-- Asset -> local file preparation
   |-- llama_flutter_android
   |-- GPU detection
   |-- CPU fallback
   |-- chat history
   |-- streaming
   |-- stop / clear / unload
```

The package intentionally contains **no UI implementation**.
