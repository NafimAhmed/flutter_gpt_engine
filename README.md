
# Flutter_GPT_Engine

> **Run GPT-style AI directly inside your Flutter app — locally, privately, and without depending on a cloud API.**

`Flutter_GPT_Engine` is a lightweight, **headless GGUF inference engine for Flutter** built for developers who want to run local large language models directly on Android devices.

It handles the difficult parts of local model execution — model selection, GGUF validation, GPU detection, CPU fallback, streaming generation, conversation history, model lifecycle, optional web retrieval, realtime model-emitted thinking, and optional device context — while leaving **100% of the UI in your hands**.

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
- Smart web-aware generation with `smartGenerate()`
- Full web-aware responses with `smartGenerateText()`
- Automatic / forced / disabled web-search modes
- Direct public URL reading
- Wikipedia search support
- Google search fallback
- Official-source hints for current technical information
- Access to retrieved sources through `lastWebSearchResult`
- Standalone web retrieval with `searchWeb()`
- Realtime model-emitted thinking support through `generationEvents`
- Automatic removal of `<think>` / `<analysis>` content from final answers
- `thinkingText`, `answerText`, and `isThinking` state
- Automatic web fallback when the local model cannot answer
- Optional `DeviceContextConfig`
- `DeviceContextMode.auto` and `DeviceContextMode.always`
- Current device date, time, timezone, and locale context
- Device / OS / app information
- Battery, network, storage, memory, and screen information
- Latitude, longitude, accuracy, altitude, speed, and heading
- Reverse-geocoded address / city information
- Optional accelerometer, gyroscope, magnetometer, and barometer context
- Optional current weather using Open-Meteo
- Device context caching and explicit location-permission helpers

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
  flutter_gpt_engine: ^0.0.7
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


## ✅ How to Enable Web Search

Web search is **optional**. Local GGUF inference still works without internet access.

To enable web search, follow these steps.

### 1. Use `flutter_gpt_engine: ^0.0.7`

```yaml
dependencies:
  flutter_gpt_engine: ^0.0.7
```

Then run:

```bash
flutter pub get
```

### 2. Add Android Internet Permission

Open:

```text
android/app/src/main/AndroidManifest.xml
```

Add this permission **before** the `<application>` tag:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Example:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:label="example"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        ...

    </application>

</manifest>
```

### 3. Enable Web Search in `LocalLlmClient`

Create the client with `WebSearchConfig`:

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    systemPrompt: 'You are a helpful AI assistant.',
    threads: 4,
    contextSize: 4096,
    maxTokens: 512,
  ),
  webSearchConfig: const WebSearchConfig(
    enabled: true,
    useWikipedia: true,
    useGoogle: true,
    directUrlFetch: true,
    useOfficialSourceHints: true,
    maxResults: 3,
    maxPageCharacters: 5000,
    maxTotalContextCharacters: 9000,
    timeout: Duration(seconds: 12),
  ),
);
```

The most important option is:

```dart
enabled: true
```

If `enabled` is `false`, web retrieval will not run.

### 4. Use a Web-Aware Generation Method

Recommended:

```dart
await for (final token in gpt.smartGenerate(
  'What is the latest stable version of Flutter?',
  searchMode: WebSearchMode.auto,
)) {
  print(token);
}
```

For a full response:

```dart
final answer = await gpt.smartGenerateText(
  'What is the latest stable version of Flutter?',
  searchMode: WebSearchMode.auto,
);

print(answer);
```

### `auto`, `always`, or `never`

Use:

```dart
WebSearchMode.auto
```

when you want the package to decide whether fresh web information is needed.

Use:

```dart
WebSearchMode.always
```

when you want to force web retrieval:

```dart
final answer = await gpt.smartGenerateText(
  'What is the latest Flutter release?',
  searchMode: WebSearchMode.always,
);
```

Use:

```dart
WebSearchMode.never
```

when the current request must stay fully local:

```dart
final answer = await gpt.smartGenerateText(
  'Summarize this private internal note.',
  searchMode: WebSearchMode.never,
);
```

### Existing `generate()` API

The normal `generate()` method remains local by default:

```dart
await for (final token in gpt.generate(
  'Explain Flutter widgets.',
)) {
  print(token);
}
```

If you want to enable web-aware behavior through `generate()`, you can use:

```dart
await for (final token in gpt.generate(
  'What is the latest stable version of Flutter?',
  useWebSearch: true,
  searchMode: WebSearchMode.auto,
)) {
  print(token);
}
```

### Check Whether Web Search Is Running

```dart
gpt.addListener(() {
  print('Searching web: ${gpt.isSearchingWeb}');
  print('Status: ${gpt.status}');
});
```

You can also inspect the retrieved sources:

```dart
final result = gpt.lastWebSearchResult;

if (result != null) {
  for (final source in result.sources) {
    print('Title: ${source.title}');
    print('URL: ${source.url}');
  }
}
```

### Quick Enable Example

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    systemPrompt: 'You are a helpful AI assistant.',
  ),
  webSearchConfig: const WebSearchConfig(
    enabled: true,
  ),
);

final answer = await gpt.smartGenerateText(
  'What is the latest stable version of Flutter?',
  searchMode: WebSearchMode.auto,
);

print(answer);
```

That is enough to enable the package's web-aware generation flow.

---

## 🌐 Smart Web Search — New in v0.0.7

`Flutter_GPT_Engine` can now combine **local GGUF inference** with optional fresh public web information.

Normal questions can still run completely locally:

```dart
final answer = await gpt.generateText(
  'Explain inheritance in Java.',
);
```

For questions that may need current information, use `smartGenerate()` or `smartGenerateText()`.

### Configure web search

Create the client with `WebSearchConfig`:

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    systemPrompt: 'You are a helpful AI assistant.',
    threads: 4,
    contextSize: 4096,
    maxTokens: 512,
  ),
  webSearchConfig: const WebSearchConfig(
    enabled: true,
    useWikipedia: true,
    useGoogle: true,
    directUrlFetch: true,
    useOfficialSourceHints: true,
    maxResults: 3,
    maxPageCharacters: 5000,
    maxTotalContextCharacters: 9000,
    timeout: Duration(seconds: 12),
  ),
);
```

### Smart streaming response

```dart
await for (final token in gpt.smartGenerate(
  'What is the latest stable version of Flutter?',
  searchMode: WebSearchMode.auto,
)) {
  print(token);
}
```

### Smart full response

```dart
final answer = await gpt.smartGenerateText(
  'What is the latest Flutter release?',
  searchMode: WebSearchMode.auto,
);

print(answer);
```

### Web search modes

```dart
WebSearchMode.auto
WebSearchMode.always
WebSearchMode.never
```

#### `WebSearchMode.auto`

The package decides whether the prompt appears to need fresh information.

```dart
final answer = await gpt.smartGenerateText(
  'Flutter er latest stable version koto?',
  searchMode: WebSearchMode.auto,
);
```

Typical current-information queries include words such as:

```text
latest
current
today
now
recent
news
price
version
release
update
weather
score
schedule
```

#### `WebSearchMode.always`

Force web retrieval for the current request:

```dart
final answer = await gpt.smartGenerateText(
  'Tell me about Flutter.',
  searchMode: WebSearchMode.always,
);
```

#### `WebSearchMode.never`

Keep the current request fully local:

```dart
final answer = await gpt.smartGenerateText(
  'Explain SOLID principles.',
  searchMode: WebSearchMode.never,
);
```

This is useful for private, sensitive, or internal application data.

### Direct URL reading

```dart
final answer = await gpt.smartGenerateText(
  '''
Read this page and summarize the latest release information:

https://docs.flutter.dev/release
''',
  searchMode: WebSearchMode.auto,
);

print(answer);
```

The flow is:

```text
Public URL
   ↓
Fetch webpage
   ↓
Extract readable content
   ↓
Build fresh web context
   ↓
Local GGUF model
   ↓
Final answer
```

### Search the web without running the LLM

```dart
final result = await gpt.searchWeb(
  'Flutter latest stable release',
);

print('Query: ${result.query}');

for (final source in result.sources) {
  print('Title: ${source.title}');
  print('URL: ${source.url}');
  print('Text: ${source.text}');
}
```

This is useful when you want to build your own source list, citation UI, search preview, result ranking, or debug screen.

### Inspect sources after generation

```dart
final result = gpt.lastWebSearchResult;

if (result != null) {
  for (final source in result.sources) {
    print(source.title);
    print(source.url);
  }
}
```

You can also observe the web-search state:

```dart
gpt.addListener(() {
  print('Searching web: ${gpt.isSearchingWeb}');
  print('Status: ${gpt.status}');
});
```

### How web-aware generation works

```text
USER QUESTION
     │
     ▼
Does the request need fresh information?
     │
 ┌───┴────┐
 │        │
No       Yes
 │        │
 ▼        ▼
Local    Public Web
GGUF      Search / URL Fetch
 │        │
 │        ▼
 │     Fresh Context
 │        │
 └────┬───┘
      ▼
 Local GGUF Model
      │
      ▼
 Final Response
```

The LLM still runs locally. The internet is used only for retrieving public information when web search is enabled and triggered.

> **Important:** API-key-free web search depends on publicly accessible webpages. Search engines may change HTML, rate-limit requests, show CAPTCHA pages, or block automated requests. JavaScript-only pages may also be difficult to read.

---

## 🧠 Realtime Thinking — New in v0.0.6

`Flutter_GPT_Engine` can now separate model-emitted thinking from the final answer.

This is designed for compatible GGUF models that generate reasoning inside tags such as:

```text
<think>
...
</think>
```

or:

```text
<analysis>
...
</analysis>
```

The normal `Stream<String>` now emits **final-answer text only**. Thinking can be observed separately through `generationEvents`, `thinkingText`, and `isThinking`.

### Enable thinking

Enable it globally:

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    showThinking: true,
  ),
);
```

Or enable it for one request:

```dart
await for (final token in gpt.smartGenerate(
  'Explain this problem step by step.',
  showThinking: true,
)) {
  print(token); // final-answer tokens only
}
```

### Listen to realtime generation events

```dart
gpt.generationEvents.listen((event) {
  if (event.isThinking) {
    print('THINKING: ${event.text}');
  }

  if (event.isSearchingWeb) {
    print('SEARCHING WEB...');
  }

  if (event.isAnswer) {
    print('ANSWER: ${event.text}');
  }

  if (event.isDone) {
    print('DONE: ${event.text}');
  }
});
```

`event.text` contains the cumulative text for the current phase.

`event.delta` contains only the newly emitted text for that event.

Available phases:

```dart
LocalLlmGenerationPhase.thinking
LocalLlmGenerationPhase.searchingWeb
LocalLlmGenerationPhase.answer
LocalLlmGenerationPhase.done
```

The client also exposes:

```dart
gpt.isThinking
gpt.thinkingText
gpt.answerText
```

When the final answer begins, the engine clears the visible thinking state so your UI can replace the thinking view with the final answer.

Thinking text is not stored as the normal assistant answer in conversation history.

---

## 🌐 Automatic Web Fallback — New in v0.0.6

`smartGenerate()` can optionally try the local model first and automatically search the public web if the completed local answer clearly indicates that it cannot answer.

Enable it in `WebSearchConfig`:

```dart
final gpt = LocalLlmClient(
  webSearchConfig: const WebSearchConfig(
    enabled: true,
    fallbackOnLocalFailure: true,
  ),
);
```

Or override it for a single request:

```dart
final answer = await gpt.smartGenerateText(
  'Tell me about this recently released tool.',
  searchMode: WebSearchMode.auto,
  fallbackOnLocalFailure: true,
);
```

The flow is:

```text
User Question
    ↓
Try Local GGUF
    ↓
Can answer?
  ┌───┴────┐
 Yes      No
  │        │
  │        ▼
  │    Web Search
  │        │
  │        ▼
  │   Fresh Context
  │        │
  └────┬───┘
       ▼
 Local GGUF Model
       ↓
 Final Answer
```

When fallback checking is enabled, the first local candidate is buffered. If it clearly fails, that failed candidate is discarded before the web-grounded answer is generated.

> `fallbackOnLocalFailure` is `false` by default so existing applications keep their previous low-latency streaming behavior unless they explicitly enable this feature.

You can also customize failure detection:

```dart
webSearchConfig: const WebSearchConfig(
  enabled: true,
  fallbackOnLocalFailure: true,
  minLocalAnswerCharacters: 20,
  localFailurePhrases: <String>[
    "i don't know",
    "i'm not sure",
    'ami jani na',
    'আমি জানি না',
  ],
),
```

---

## 📱 Device Context — New in v0.0.6

Device Context lets the local GGUF model use optional live information from the device.

Supported context can include:

- Current date and time
- Timezone
- Locale
- Device model / manufacturer
- Android / OS information
- App version and build number
- Battery percentage and charging state
- Battery saver state
- Network connectivity
- Memory information
- Storage information
- Screen information
- Latitude and longitude
- Location accuracy
- Altitude
- Speed
- Heading
- Reverse-geocoded address / city
- Accelerometer
- Gyroscope
- Magnetometer
- Barometer, when available
- Current weather through Open-Meteo

Device Context is **disabled by default**.

### Enable Device Context

```dart
final gpt = LocalLlmClient(
  deviceContextConfig: const DeviceContextConfig(
    enabled: true,
    mode: DeviceContextMode.auto,

    includeDateTime: true,
    includeTimezone: true,
    includeLocale: true,

    includeDeviceInfo: true,
    includeOsInfo: true,
    includeAppInfo: true,

    includeBattery: true,
    includeNetwork: true,
    includeStorage: true,
    includeMemory: true,
    includeScreenInfo: true,

    includeLocation: true,
    includeAddress: true,
    includeAltitude: true,
    includeSpeed: true,
    includeHeading: true,

    includeSensors: false,
    includeBarometer: false,

    includeWeather: true,
  ),
);
```

### `DeviceContextMode.auto`

Recommended for most apps:

```dart
mode: DeviceContextMode.auto
```

In `auto` mode, the package tries to collect only the device context relevant to the current question.

For example:

```text
"What time is it?"
        ↓
Date / time

"Battery koto?"
        ↓
Battery

"Amar location kothay?"
        ↓
Location

"Amar ekhane weather kemon?"
        ↓
Location + weather

"Explain Java inheritance"
        ↓
No unnecessary location/weather collection
```

### `DeviceContextMode.always`

```dart
mode: DeviceContextMode.always
```

This collects every enabled context category for every generation.

### Enable or disable Device Context at runtime

```dart
gpt.setDeviceContextEnabled(true);
```

Disable it:

```dart
gpt.setDeviceContextEnabled(false);
```

Update the full runtime configuration:

```dart
gpt.updateDeviceContextConfig(
  gpt.deviceContextConfig.copyWith(
    enabled: true,
    includeLocation: false,
    includeWeather: false,
  ),
);
```

### Location permission

By default:

```dart
requestLocationPermissionWhenNeeded: false
```

This prevents the package from unexpectedly opening a location permission dialog.

The host application can explicitly request permission:

```dart
final granted = await gpt.requestDeviceLocationPermission();
```

Check permission:

```dart
final granted = await gpt.hasDeviceLocationPermission();
```

If you intentionally want the package to request permission when a location-dependent question requires it:

```dart
deviceContextConfig: const DeviceContextConfig(
  enabled: true,
  requestLocationPermissionWhenNeeded: true,
),
```

### Collect Device Context manually

```dart
final snapshot = await gpt.collectDeviceContext(
  prompt: 'Show my current device information',
);

print(snapshot.toPromptContext());
```

### Device Context cache

```dart
deviceContextConfig: const DeviceContextConfig(
  enabled: true,
  basicCacheDuration: Duration(minutes: 5),
  locationCacheDuration: Duration(minutes: 2),
  weatherCacheDuration: Duration(minutes: 15),
  sensorTimeout: Duration(seconds: 2),
  locationTimeout: Duration(seconds: 10),
  weatherTimeout: Duration(seconds: 8),
),
```

Clear cached device information:

```dart
gpt.clearDeviceContextCache();
```

### Current weather

Current weather is fetched from Open-Meteo using the current device location.

```text
Device GPS
    ↓
Latitude / Longitude
    ↓
Open-Meteo
    ↓
Current Weather
    ↓
Local GGUF Context
```

No weather API key is required.

If location permission, internet access, device data, or weather data is unavailable, the engine treats that information as unavailable instead of intentionally inventing a live value.

---

## 🚀 Performance Tuning — New in v0.0.7

The engine can measure the actual device/model combination instead of assuming
that more CPU threads or GPU offload is always faster.

### Benchmark the current profile

```dart
final result = await gpt.benchmark();

print('TTFT: ${result.timeToFirstToken.inMilliseconds} ms');
print('Speed: ${result.tokensPerSecond.toStringAsFixed(2)} tok/s');
print('Threads: ${result.threads}');
print('GPU layers: ${result.gpuLayers}');
```

The benchmark does not add messages to normal chat history.

### Auto-tune CPU threads and GPU offload

```dart
final tuned = await gpt.autoTune();

print('Selected threads: ${tuned.threads}');
print('Selected GPU layers: ${tuned.gpuLayers}');
print('Speed: ${tuned.selected.tokensPerSecond.toStringAsFixed(2)} tok/s');
```

`autoTune()` tests a small set of CPU thread counts and, when Vulkan is
available, safe GPU layer candidates. It then reloads the model using the
highest measured score. Tuning is opt-in because it reloads the model several
times and runs short local generations.

You can inspect the currently active profile:

```dart
print(gpt.activeThreads);
print(gpt.activeGpuLayers);
print(gpt.hasRuntimePerformanceProfile);
```

For a conservative device-aware thread count without benchmarking, set:

```dart
LocalLlmConfig(
  threads: 0,
)
```

Conversation history is also bounded by both message count and character count:

```dart
LocalLlmConfig(
  maxHistoryMessages: 8,
  maxHistoryCharacters: 12000,
)
```

Set `maxHistoryCharacters: 0` to disable the character budget.

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
    showThinking: false,
  ),
);
```

### 🧠 Context Size: Speed vs Memory

`contextSize` controls how much text the local model can keep inside its active
context window while generating a response.

The default is:

```dart
LocalLlmConfig(
  contextSize: 4096,
)
```

You can change it to any value supported by your GGUF model and device:

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    contextSize: 2048,
  ),
);
```

Or use a larger context:

```dart
final gpt = LocalLlmClient(
  config: const LocalLlmConfig(
    contextSize: 8192,
  ),
);
```

#### Which value should I use?

| Context size | Best for | Speed / memory |
|---|---|---|
| `2048` | Fast mobile chat, short Q&A, commands | ⚡ Faster, lower RAM |
| `4096` | General-purpose chat | ✅ Balanced — default |
| `8192+` | Long conversations, large prompts, documents | 🧠 More context, more RAM, potentially slower |

A smaller context can reduce KV-cache memory usage and may improve response
startup time on mobile devices.

A larger context gives the model more room for conversation history, long
prompts, web-grounded context, or document content, but it requires more memory
and can increase prompt-processing time.

> **Recommended:** Keep `4096` unless you have a specific reason to change it.
> If response speed is the priority, try `2048`. If long-context quality is
> more important and the device has enough RAM, try `8192` or higher.

#### Important

`contextSize` is a maximum context capacity. Setting it to `4096` does **not**
mean the engine processes 4096 tokens for every request. A short prompt still
processes only the tokens it actually contains.

Very large values are not automatically better. The usable maximum depends on:

- the GGUF model
- available device RAM
- native backend support
- conversation history size
- prompt / web / device context size

For mobile apps, benchmark the real device instead of assuming that a larger
context is always better.

---

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
| `showThinking` | Exposes compatible model-emitted thinking through `generationEvents` / `thinkingText` |

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
  print('Searching Web: ${gpt.isSearchingWeb}');
  print('Thinking: ${gpt.isThinking}');
  print('Status: ${gpt.status}');
  print('Thinking Text: ${gpt.thinkingText}');
  print('Answer Text: ${gpt.answerText}');
});
```

Available state:

```dart
gpt.isLoading
gpt.isLoaded
gpt.isGenerating
gpt.isSearchingWeb
gpt.isThinking
gpt.status
gpt.model
gpt.messages
gpt.thinkingText
gpt.answerText
gpt.lastWebSearchResult
gpt.deviceContextConfig
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

In `0.0.7`, model-emitted thinking is kept separate from the normal assistant answer and is not stored as the final conversation-history response.

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

### Internet permission for web search

If you use the web-search features introduced in `0.0.4`, add this permission to:

```text
android/app/src/main/AndroidManifest.xml
```

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### Location permission for Device Context

If you enable location, address, altitude, speed, heading, or current local weather, also add:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

The package does not require location permission for normal local GGUF inference, date/time, basic device information, or ordinary web search.

Normal local GGUF inference does not require internet access after the model is available on the device.


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

When web-aware generation is enabled and triggered, the search query or requested public URL is sent over the network so public web content can be retrieved. The final LLM generation still runs through the local GGUF model.

For sensitive or internal information, disable web retrieval for that turn:

```dart
searchMode: WebSearchMode.never
```

When Device Context is enabled, the host application controls which device-data categories are available to the engine. Device Context is disabled by default.

Location-related context can require Android runtime permission.

When current weather is enabled and needed, the package uses the current latitude/longitude to request current weather from Open-Meteo. Disable `includeWeather` or location-related context if your application should not use that network-backed feature.


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
- Offline-first assistants with fresh web knowledge
- Public URL summarizers
- Documentation assistants
- Current-information assistants
- Device-aware local AI assistants
- Location-aware assistants
- On-device troubleshooting assistants
- Local AI apps with realtime thinking UI

---

## 🎯 Design Philosophy

The goal is simple:

> **The package should handle local AI inference.  
> The developer should control everything else.**

No forced UI.  
No forced architecture.  
No cloud API dependency for inference.

Just a reusable Flutter engine for running compatible GGUF language models locally.

With `0.0.4`, the engine added optional fresh public web retrieval. With `0.0.6`, it can also expose model-emitted thinking, automatically fall back to web retrieval when the local model cannot answer, and optionally provide device-aware context while keeping the host application in control.

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
- Whether web search / fallback is enabled
- Whether Device Context is enabled

---

## 📄 License

See the `LICENSE` file included with this package.

---

## ⭐ Support

If this package helps your project, consider giving the repository a star and sharing it with other Flutter developers.

**Build your UI. Choose your model. Run AI locally.**
---

## 👨‍💻 Developer

**Nafim Ahmed**

🌐 **Portfolio:** [https://nafimahmed.github.io](https://nafimahmed.github.io)  
📧 **Email:** [recentnafimahmed@gmail.com](mailto:recentnafimahmed@gmail.com)

