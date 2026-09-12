# Flutter_GPT_Engine

> **Run GPT-style AI directly inside your Flutter app — locally, privately, and without depending on a cloud API.**

`Flutter_GPT_Engine` is a lightweight, **headless GGUF inference engine for Flutter** built for developers who want to run local large language models directly on Android devices.

It handles the difficult parts of local model execution — model selection, GGUF validation, GPU detection, CPU fallback, streaming generation, conversation history, and model lifecycle — while leaving **100% of the UI in your hands**.

No chat screen.  
No predefined message bubbles.  
No forced theme.  
No opinionated UI architecture.

You build the experience. `Flutter_GPT_Engine` provides the AI engine.

---

## ✨ Why Flutter_GPT_Engine?

Cloud AI is powerful, but not every application needs to send every prompt to a remote server.

With `Flutter_GPT_Engine`, your Flutter app can run compatible **GGUF models locally on the user's Android device**.

That means:

- 🔒 **Private by design** — prompts can stay on the device
- 🌐 **Offline inference** — no internet connection is required after the model is available locally
- 💳 **No per-request API cost**
- ⚡ **Streaming responses**
- 🎮 **GPU acceleration when supported**
- 🧠 **Automatic CPU fallback**
- 🗂️ **Conversation history management**
- 🎨 **Complete UI freedom**

The package is designed as an **engine layer**, not a UI framework.

---

## 🚀 Features

`Flutter_GPT_Engine` currently supports:

- GGUF model selection using File Picker
- Loading a GGUF model from Flutter assets
- Loading a GGUF model from a direct filesystem path
- GGUF file validation
- Automatic GPU detection
- GPU → CPU fallback if GPU loading fails
- Configurable context size
- Configurable thread count
- Configurable generation settings
- Streaming token generation
- Full-response generation
- Conversation history
- Stop generation
- Clear conversation
- Unload model
- Model lifecycle management
- `ChangeNotifier`-based state updates
- Optional persistence of a picked GGUF file into Application Support

---

## 🎨 No UI Included — By Design

`Flutter_GPT_Engine` intentionally provides **no UI implementation**.

It does **not** include:

- Chat screens
- Message bubbles
- Text fields
- Send buttons
- App bars
- Themes
- Navigation
- State-management opinions

Your application decides how the AI should look and behave.

```text
YOUR FLUTTER APP
│
├── Your Chat UI
├── Your TextField
├── Your Send Button
├── Your Theme
├── Your State Management
│
└── Flutter_GPT_Engine
    ├── GGUF model loading
    ├── File Picker
    ├── GPU detection
    ├── CPU fallback
    ├── Local inference
    ├── Streaming
    ├── Conversation history
    └── Model lifecycle
```

---

## 📦 Installation

Add the package to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  flutter_gpt_engine: ^0.0.3
```

Then run:

```bash
flutter pub get
```

Import it:

```dart
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';
```

---

## 🤖 1. Create the AI Client

Create one `LocalLlmClient` instance and keep it alive for as long as you need the model.

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

---

## 📂 2. Let the User Pick a GGUF Model

You can connect this method to any button in your own UI.

```dart
final selected = await gpt.pickModel();

if (selected) {
  print('Loaded model: ${gpt.model?.name}');
}
```

The package opens the system File Picker and accepts `.gguf` files.

### Persist the selected model

If you want the selected GGUF file copied into the app's Application Support directory:

```dart
await gpt.pickModel(
  persist: true,
);
```

This can be useful when the selected file comes from temporary or cache-backed storage.

> Large models may take time and additional storage when copied.

---

## 📦 3. Load a Model from Flutter Assets

First declare the model in the host application's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/qwen.gguf
```

Then load it:

```dart
await gpt.loadAsset(
  'assets/models/qwen.gguf',
);
```

Flutter assets are not normal filesystem files, so the package prepares a local copy before loading the model.

> For very large GGUF files, File Picker or direct file loading is usually more practical than bundling the model inside the application.

---

## 🗃️ 4. Load a Model from a Direct File Path

If your application already knows the model path:

```dart
await gpt.loadModel(
  '/storage/emulated/0/Download/model.gguf',
);
```

The engine validates the file before attempting to load it.

---

## 💬 5. Generate a Streaming Response

Use `generate()` when you want GPT-style token streaming.

```dart
await for (final token in gpt.generate('Hello!')) {
  print(token);
}
```

Your UI decides how each token is rendered.

For example:

```dart
String response = '';

await for (final token in gpt.generate('Explain Flutter in Bangla.')) {
  response += token;

  setState(() {
    // Update your own message bubble here.
  });
}
```

---

## 📝 6. Get the Complete Response

If you do not need token-by-token streaming:

```dart
final answer = await gpt.generateText(
  'Explain Flutter in Bangla.',
);

print(answer);
```

---

## ⚙️ 7. Configure Generation

You can customize model behavior through `LocalLlmConfig`.

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    systemPrompt:
        'You are a helpful offline assistant. '
        'Reply in the same language as the user when practical.',

    threads: 4,
    contextSize: 4096,

    // null = auto-detect GPU
    // 0    = CPU only
    gpuLayers: null,

    temperature: 0.60,
    topP: 0.90,
    topK: 40,
    repeatPenalty: 1.15,

    maxTokens: 512,
    maxHistoryMessages: 8,
  ),
);
```

### Important options

| Option | Purpose |
|---|---|
| `systemPrompt` | Defines the assistant's behavior |
| `threads` | CPU thread count |
| `contextSize` | Model context window used by the engine |
| `gpuLayers` | GPU layer configuration |
| `temperature` | Controls randomness |
| `topP` | Nucleus sampling |
| `topK` | Limits token candidates |
| `repeatPenalty` | Reduces repetitive output |
| `maxTokens` | Maximum generated tokens |
| `maxHistoryMessages` | Number of previous messages included in context |

---

## 🎮 GPU Detection and CPU Fallback

By default:

```dart
gpuLayers: null
```

means the engine will attempt to detect GPU capability automatically.

If GPU loading fails, `Flutter_GPT_Engine` automatically retries using:

```dart
gpuLayers: 0
```

which runs the model on CPU.

You can also force CPU-only mode:

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    gpuLayers: 0,
  ),
);
```

---

## 📡 8. Observe Engine State

`LocalLlmClient` extends `ChangeNotifier`.

You can listen to state changes from any UI architecture you prefer:

```dart
gpt.addListener(() {
  print('Loading: ${gpt.isLoading}');
  print('Loaded: ${gpt.isLoaded}');
  print('Generating: ${gpt.isGenerating}');
  print('Status: ${gpt.status}');
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

This makes it easy to integrate with:

- `setState`
- Provider
- Riverpod
- BLoC
- Cubit
- GetX
- MobX
- any custom architecture

---

## 🧠 9. Conversation History

The engine automatically keeps user and assistant messages.

```dart
final messages = gpt.messages;

for (final message in messages) {
  print('${message.role}: ${message.text}');
}
```

A message contains:

```dart
message.role
message.text
message.createdAt
```

Your UI can render these however you want.

---

## ⏹️ 10. Stop Generation

```dart
await gpt.stop();
```

Useful for your own GPT-style **Stop** button.

---

## 🧹 11. Clear the Conversation

```dart
await gpt.clearChat();
```

This clears stored conversation history and resets the model context used by the package.

---

## 📤 12. Unload the Model

```dart
await gpt.unloadModel();
```

Useful when switching models or freeing native resources.

---

## ♻️ 13. Dispose

When the client is no longer needed:

```dart
gpt.dispose();
```

For deterministic native cleanup:

```dart
await gpt.unloadModel();
gpt.dispose();
```

---

## 🧩 Minimal Example

```dart
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    systemPrompt: 'You are a helpful offline AI assistant.',
  ),
);

Future<void> startAi() async {
  final selected = await gpt.pickModel();

  if (!selected) {
    return;
  }

  await for (final token in gpt.generate('Hello!')) {
    print(token);
  }
}
```

That is enough to:

1. Open File Picker
2. Select a GGUF model
3. Load it locally
4. Run inference
5. Stream the answer

Your application handles everything visual.

---

## 🏗️ Architecture

```text
┌─────────────────────────────────────┐
│          YOUR FLUTTER APP           │
│                                     │
│  UI • Theme • Navigation • State    │
│  Chat bubbles • Input • Buttons     │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│       Flutter_GPT_Engine            │
│                                     │
│  • Model selection                  │
│  • GGUF validation                  │
│  • Asset preparation                │
│  • GPU detection                    │
│  • CPU fallback                     │
│  • Streaming generation             │
│  • Conversation history             │
│  • Model lifecycle                  │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│       llama_flutter_android         │
│                                     │
│        Local GGUF Inference         │
└─────────────────────────────────────┘
```

---

## 📱 Platform Support

Current inference backend:

```text
Android ✅
iOS     ❌ Not currently supported
Web     ❌
Windows ❌
macOS   ❌
Linux   ❌
```

The package currently uses `llama_flutter_android`, so it is Android-focused.

---

## ⚠️ Android Requirement

`llama_flutter_android` requires Android API 26 or newer.

In your Android app:

```kotlin
android {
    defaultConfig {
        minSdk = 26
    }
}
```

If your project uses:

```kotlin
minSdk = flutter.minSdkVersion
```

replace it with:

```kotlin
minSdk = 26
```

---

## 🪟 Windows Development Note

If your Flutter project is on one Windows drive and the Pub cache is on another drive, Kotlin incremental compilation can sometimes produce cache errors.

Example:

```text
Project:   D:\development\my_app
Pub Cache: C:\Users\User\AppData\Local\Pub\Cache
```

If that happens, add this to:

```text
android/gradle.properties
```

```properties
kotlin.incremental=false
```

Then clean and rebuild:

```bash
flutter clean
flutter pub get
flutter run
```

---


## 🤗 Download GGUF Models from Hugging Face

Need a model to get started?

You can download compatible **GGUF models** from Hugging Face:

👉 [Browse GGUF models on Hugging Face](https://huggingface.co/models?search=gguf)

For a small mobile-friendly model, you can start with:

👉 [Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF)

Example file:

```text
qwen2.5-0.5b-instruct-q4_k_m.gguf
```

After downloading the `.gguf` file, your app can let the user select it using:

```dart
final selected = await gpt.pickModel();
```

Or load it directly from a known path:

```dart
await gpt.loadModel(
  '/storage/emulated/0/Download/qwen2.5-0.5b-instruct-q4_k_m.gguf',
);
```

> **Tip:** For Android devices, smaller quantized models such as `Q4_K_M` are often a good starting point because they provide a practical balance between model size, memory usage, and response quality.

> Always check the model card and license on Hugging Face before redistributing or using a model in production.

---

## 🧠 Choosing a Model

`Flutter_GPT_Engine` does **not** bundle an AI model.

You provide the GGUF model yourself.

For mobile devices, smaller quantized models are generally more practical because model size, RAM usage, context size, and device performance directly affect inference speed.

Typical model file:

```text
*.gguf
```

Example:

```text
qwen2.5-0.5b-instruct-q4_k_m.gguf
```

Always verify the license and usage terms of any model you distribute or recommend.

---

## 🔐 Privacy

The inference engine is designed to run the model locally.

```text
Prompt
  ↓
Your Flutter App
  ↓
Flutter_GPT_Engine
  ↓
Local GGUF Model
  ↓
Generated Response
```

The package itself does not require a cloud LLM API for generation.

Your own application may still use networking for other features, so overall privacy depends on how you build your app.

---

## 💡 Use Cases

You can use `Flutter_GPT_Engine` to build:

- Offline AI assistants
- Private enterprise assistants
- Educational AI apps
- Field-service assistants
- Local productivity tools
- Offline Q&A apps
- AI-powered ERP/mobile tools
- Personal assistants
- Experimental on-device LLM apps

---

## 🎯 Design Philosophy

The goal is simple:

> **The package should handle local AI inference.  
> The developer should control everything else.**

No forced UI.  
No forced architecture.  
No cloud API dependency for inference.

Just a reusable Flutter engine for running compatible GGUF language models locally.

---

## 🤝 Contributions

Issues, suggestions, improvements, and pull requests are welcome.

If you report a bug, please include:

- Flutter version
- Android version
- Device model
- GGUF model name
- Package version
- Relevant logs

---

## 📄 License

See the `LICENSE` file included with this package.

---

## ⭐ Support

If this package helps your project, consider giving the repository a star and sharing it with other Flutter developers.

**Build your UI. Choose your model. Run AI locally.**
