import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter GPT Engine',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const AiExamplePage(),
    );
  }
}

class AiExamplePage extends StatefulWidget {
  const AiExamplePage({super.key});

  @override
  State<AiExamplePage> createState() => _AiExamplePageState();
}

class _AiExamplePageState extends State<AiExamplePage> {
  late final LocalLlmClient _gpt;

  StreamSubscription<LocalLlmGenerationEvent>? _generationSubscription;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loadingModel = false;
  bool _generating = false;

  String _status = 'Select a GGUF model';

  String _thinkingText = '';
  String _answerText = '';

  final List<_ChatMessage> _messages = <_ChatMessage>[];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _gpt = LocalLlmClient(
      // ========================================================
      // LOCAL MODEL CONFIG
      // ========================================================

      config: const LocalLlmConfig(
        systemPrompt: '''
You are a helpful AI assistant.

LANGUAGE RULES:
- Always reply in the same language and writing style as the user.
- If the user writes English, reply in English.
- If the user writes Bangla, reply in Bangla.
- If the user writes Banglish, reply in Banglish.

DEVICE CONTEXT RULES:
- The application may provide real device information.
- Use device information when relevant.
- Never invent unavailable device information.
- Never invent location, weather, battery, network, date or time.
''',

        threads: 4,
        contextSize: 4096,

        // null = GPU auto detect
        gpuLayers: null,

        temperature: 0.60,
        topP: 0.90,
        topK: 40,
        repeatPenalty: 1.15,

        maxTokens: 512,
        maxHistoryMessages: 8,

        // Realtime model-emitted thinking support.
        showThinking: true,
      ),

      // ========================================================
      // WEB SEARCH
      // ========================================================

      webSearchConfig: const WebSearchConfig(
        enabled: true,

        useWikipedia: true,
        useGoogle: true,
        directUrlFetch: true,
        useOfficialSourceHints: true,

        // Local model যদি clearly answer না জানে,
        // package automatically web search করবে.
        fallbackOnLocalFailure: true,

        maxResults: 3,
        maxPageCharacters: 5000,
        maxTotalContextCharacters: 9000,

        timeout: Duration(
          seconds: 12,
        ),
      ),

      // ========================================================
      // DEVICE CONTEXT
      // ========================================================

      deviceContextConfig: const DeviceContextConfig(
        // Device context ON.
        enabled: true,

        // Other device data question অনুযায়ী collect হবে.
        mode: DeviceContextMode.auto,

        // Basic
        includeDateTime: true,
        includeTimezone: true,
        includeLocale: true,

        // Device
        includeDeviceInfo: true,
        includeOsInfo: true,
        includeAppInfo: true,

        // System
        includeBattery: true,
        includeNetwork: true,
        includeStorage: true,
        includeMemory: true,
        includeScreenInfo: true,

        // Location
        includeLocation: true,
        includeAddress: true,
        includeAltitude: true,
        includeSpeed: true,
        includeHeading: true,

        // Sensors
        includeSensors: true,
        includeBarometer: true,

        // Weather
        includeWeather: true,

        // Location/weather related প্রশ্ন করলে
        // প্রয়োজন হলে permission dialog দেখাবে.
        requestLocationPermissionWhenNeeded: true,

        basicCacheDuration: Duration(
          minutes: 5,
        ),

        locationCacheDuration: Duration(
          minutes: 2,
        ),

        weatherCacheDuration: Duration(
          minutes: 15,
        ),

        sensorTimeout: Duration(
          seconds: 2,
        ),

        locationTimeout: Duration(
          seconds: 10,
        ),

        weatherTimeout: Duration(
          seconds: 8,
        ),
      ),
    );

    _listenGenerationEvents();
  }

  // ============================================================
  // MODEL PICK + LOAD
  // ============================================================

  Future<void> _pickAndLoadModel() async {
    if (_loadingModel || _generating) {
      return;
    }

    setState(() {
      _loadingModel = true;
      _status = 'Selecting model...';
    });

    try {
      final bool loaded = await _gpt.pickModel(
        // Selected model app-private storage এ copy হবে.
        persist: true,
      );

      if (!mounted) {
        return;
      }

      if (!loaded) {
        setState(() {
          _status = _gpt.isLoaded
              ? 'Ready'
              : 'Model selection cancelled';
        });

        return;
      }

      setState(() {
        _status =
        'Ready • ${_gpt.model?.name ?? "GGUF Model"}';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Model load error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingModel = false;
        });
      }
    }
  }

  // ============================================================
  // GENERATION EVENTS
  // ============================================================

  void _listenGenerationEvents() {
    _generationSubscription =
        _gpt.generationEvents.listen(
              (LocalLlmGenerationEvent event) {
            if (!mounted) {
              return;
            }

            // ======================================================
            // THINKING
            // ======================================================

            if (event.isThinking) {
              setState(() {
                _thinkingText = event.text;
                _status = 'Thinking...';
              });

              _scrollToBottom();

              return;
            }

            // ======================================================
            // SEARCHING WEB
            // ======================================================

            if (event.isSearchingWeb) {
              setState(() {
                _status = 'Searching web...';
              });

              return;
            }

            // ======================================================
            // ANSWER
            // ======================================================

            if (event.isAnswer) {
              setState(() {
                // Final answer শুরু হলেই
                // thinking UI remove হবে.
                _thinkingText = '';

                _answerText = event.text;

                if (_messages.isNotEmpty &&
                    _messages.last.role == 'assistant') {
                  _messages.last.text = event.text;
                }

                _status = 'Generating...';
              });

              _scrollToBottom();

              return;
            }

            // ======================================================
            // DONE
            // ======================================================

            if (event.isDone) {
              setState(() {
                _thinkingText = '';
                _answerText = event.text;

                if (_messages.isNotEmpty &&
                    _messages.last.role == 'assistant') {
                  _messages.last.text = event.text;
                }

                _generating = false;
                _status = 'Ready';
              });

              _scrollToBottom();
            }
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }

            setState(() {
              _generating = false;
              _thinkingText = '';
              _status = 'Error: $error';
            });
          },
        );
  }

  // ============================================================
  // DATE + TIME
  // ALWAYS ON
  // ============================================================

  String _buildAlwaysDateTimeContext() {
    final DateTime now = DateTime.now();

    final Duration offset = now.timeZoneOffset;

    final String sign =
    offset.isNegative ? '-' : '+';

    final int totalMinutes =
    offset.inMinutes.abs();

    final int offsetHour =
        totalMinutes ~/ 60;

    final int offsetMinute =
        totalMinutes % 60;

    final String offsetText =
        '$sign'
        '${offsetHour.toString().padLeft(2, '0')}:'
        '${offsetMinute.toString().padLeft(2, '0')}';

    return '''
CURRENT DEVICE DATE AND TIME:

Current Date: ${_formatDate(now)}
Current Time: ${_formatTime(now)}
Current Day: ${_weekday(now.weekday)}
Timezone Name: ${now.timeZoneName}
UTC Offset: $offsetText
ISO DateTime: ${now.toIso8601String()}

IMPORTANT DATE/TIME RULES:
- This information comes directly from the user's device.
- Treat this as the authoritative current date and time.
- If the user asks "what time is it", "ajke date koto", "today", "now",
  "current time", "current date", "what day is today", or similar,
  answer using this device information.
- Never use pretrained model knowledge to guess the current date or time.
''';
  }

  // ============================================================
  // DATE FORMAT
  // ============================================================

  String _formatDate(DateTime dateTime) {
    final String year =
    dateTime.year.toString();

    final String month =
    dateTime.month
        .toString()
        .padLeft(2, '0');

    final String day =
    dateTime.day
        .toString()
        .padLeft(2, '0');

    return '$year-$month-$day';
  }

  // ============================================================
  // TIME FORMAT
  // ============================================================

  String _formatTime(DateTime dateTime) {
    int hour = dateTime.hour;

    final String minute =
    dateTime.minute
        .toString()
        .padLeft(2, '0');

    final String second =
    dateTime.second
        .toString()
        .padLeft(2, '0');

    final String period =
    hour >= 12 ? 'PM' : 'AM';

    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }

    return '${hour.toString().padLeft(2, '0')}:'
        '$minute:$second $period';
  }

  // ============================================================
  // WEEKDAY
  // ============================================================

  String _weekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';

      case DateTime.tuesday:
        return 'Tuesday';

      case DateTime.wednesday:
        return 'Wednesday';

      case DateTime.thursday:
        return 'Thursday';

      case DateTime.friday:
        return 'Friday';

      case DateTime.saturday:
        return 'Saturday';

      case DateTime.sunday:
        return 'Sunday';

      default:
        return '';
    }
  }

  // ============================================================
  // RUNTIME SYSTEM PROMPT
  // ============================================================

  String get _runtimeSystemPrompt {
    return '''
You are a helpful AI assistant.

LANGUAGE RULES:
- Always reply in the same language and writing style as the user's latest message.
- English message -> English reply.
- Bangla message -> Bangla reply.
- Banglish message -> Banglish reply.
- Keep technical names, file names, package names, APIs and code unchanged.

${_buildAlwaysDateTimeContext()}

DEVICE CONTEXT RULES:
- Flutter GPT Engine may provide current device information.
- Device information is newer and more reliable than pretrained knowledge.
- Use device information only when relevant to the user's question.
- Never invent unavailable device information.
- Never invent battery percentage.
- Never invent network state.
- Never invent GPS coordinates.
- Never invent altitude.
- Never invent weather data.
- Never invent device model or operating system information.
- If a requested device value is unavailable, clearly say that it is unavailable.

WEB SEARCH RULES:
- Fresh public web information may be supplied when required.
- Fresh web information is newer than pretrained model knowledge.
- For current/latest/news/version/release/price/weather questions,
  prefer supplied fresh information.
- Never invent a current fact when it cannot be verified.

ANSWER STYLE:
- Answer the user's actual question directly.
- Be concise unless the user asks for details.
''';
  }

  // ============================================================
  // SEND
  // ============================================================

  Future<void> _sendMessage() async {
    final String text =
    _controller.text.trim();

    if (text.isEmpty) {
      return;
    }

    // Model must be loaded first.
    if (!_gpt.isLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a GGUF model first.',
          ),
        ),
      );

      return;
    }

    if (_generating) {
      return;
    }

    FocusScope.of(context).unfocus();

    _controller.clear();

    setState(() {
      // User message
      _messages.add(
        _ChatMessage(
          role: 'user',
          text: text,
        ),
      );

      // Empty assistant message.
      // Stream events will update this message.
      _messages.add(
        _ChatMessage(
          role: 'assistant',
          text: '',
        ),
      );

      _thinkingText = '';
      _answerText = '';

      _generating = true;
      _status = 'Preparing...';
    });

    _scrollToBottom();

    try {
      // ========================================================
      // SMART GENERATE
      // ========================================================

      await for (final String _ in _gpt.smartGenerate(
        text,

        // IMPORTANT:
        // This is rebuilt EVERY message,
        // therefore Date/Time is always current.
        systemPrompt: _runtimeSystemPrompt,

        // Realtime Think
        showThinking: true,

        // Local model fail করলে web fallback
        fallbackOnLocalFailure: true,

        // Latest/current/etc -> auto web search
        searchMode: WebSearchMode.auto,
      )) {
        // No UI work required here.
        //
        // generationEvents listener handles:
        // thinking
        // searchingWeb
        // answer
        // done
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _generating = false;
        _thinkingText = '';

        // Extra final safety.
        if (_gpt.answerText.trim().isNotEmpty) {
          _answerText =
              _gpt.answerText.trim();

          if (_messages.isNotEmpty &&
              _messages.last.role == 'assistant') {
            _messages.last.text =
                _answerText;
          }
        }

        _status = 'Ready';
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _generating = false;
        _thinkingText = '';

        if (_messages.isNotEmpty &&
            _messages.last.role == 'assistant' &&
            _messages.last.text.trim().isEmpty) {
          _messages.last.text =
          'Error: $e';
        }

        _status = 'Error';
      });

      _scrollToBottom();
    }
  }

  // ============================================================
  // STOP
  // ============================================================

  Future<void> _stopGeneration() async {
    await _gpt.stop();

    if (!mounted) {
      return;
    }

    setState(() {
      _generating = false;

      // Thinking immediately remove.
      _thinkingText = '';

      // Keep already-generated final answer.
      if (_gpt.answerText.trim().isNotEmpty &&
          _messages.isNotEmpty &&
          _messages.last.role == 'assistant') {
        _messages.last.text =
            _gpt.answerText.trim();
      }

      _status = 'Stopped';
    });

    _scrollToBottom();
  }

  // ============================================================
  // SCROLL
  // ============================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        if (!_scrollController.hasClients) {
          return;
        }

        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(
            milliseconds: 180,
          ),
          curve: Curves.easeOut,
        );
      },
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _generationSubscription?.cancel();

    _controller.dispose();
    _scrollController.dispose();

    _gpt.dispose();

    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        title: const Text(
          'Flutter GPT Engine',
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: SafeArea(
        child: Column(
          children: [
            // ==================================================
            // MODEL SELECT BUTTON
            // ==================================================

            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                6,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  _loadingModel || _generating
                      ? null
                      : _pickAndLoadModel,

                  icon: _loadingModel
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(
                    Icons.folder_open,
                  ),

                  label: Text(
                    _loadingModel
                        ? 'Loading Model...'
                        : _gpt.isLoaded
                        ? 'Change GGUF Model'
                        : 'Select GGUF Model',
                  ),
                ),
              ),
            ),

            // ==================================================
            // MODEL NAME
            // ==================================================

            if (_gpt.isLoaded)
              Padding(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.memory,
                      size: 16,
                    ),

                    const SizedBox(
                      width: 6,
                    ),

                    Expanded(
                      child: Text(
                        _gpt.model?.name ??
                            'GGUF Model',
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style:
                        Theme.of(context)
                            .textTheme
                            .bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

            // ==================================================
            // STATUS
            // ==================================================

            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                6,
                16,
                8,
              ),
              child: Row(
                children: [
                  if (_loadingModel ||
                      _generating) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),

                    const SizedBox(
                      width: 8,
                    ),
                  ],

                  Expanded(
                    child: Text(
                      _status,
                      style:
                      Theme.of(context)
                          .textTheme
                          .bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(
              height: 1,
            ),

            // ==================================================
            // CHAT AREA
            // ==================================================

            Expanded(
              child: _messages.isEmpty &&
                  _thinkingText
                      .trim()
                      .isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                controller:
                _scrollController,

                padding:
                const EdgeInsets.all(
                  16,
                ),

                itemCount:
                _messages.length +
                    (_thinkingText
                        .trim()
                        .isNotEmpty
                        ? 1
                        : 0),

                itemBuilder:
                    (context, index) {
                  if (index <
                      _messages.length) {
                    final _ChatMessage
                    message =
                    _messages[index];

                    // Empty assistant message
                    // final output না আসা পর্যন্ত
                    // bubble দেখাবো না.
                    if (message.role ==
                        'assistant' &&
                        message.text
                            .trim()
                            .isEmpty) {
                      return const SizedBox
                          .shrink();
                    }

                    return _MessageBubble(
                      message: message,
                    );
                  }

                  // ======================================
                  // THINKING
                  // ======================================

                  return _ThinkingBubble(
                    text: _thinkingText,
                  );
                },
              ),
            ),

            const Divider(
              height: 1,
            ),

            // ==================================================
            // INPUT AREA
            // ==================================================

            Padding(
              padding: const EdgeInsets.all(
                12,
              ),
              child: Row(
                crossAxisAlignment:
                CrossAxisAlignment.end,
                children: [
                  // ============================================
                  // TEXT INPUT
                  // ============================================

                  Expanded(
                    child: TextField(
                      controller: _controller,

                      enabled:
                      !_loadingModel,

                      minLines: 1,
                      maxLines: 5,

                      textInputAction:
                      TextInputAction.send,

                      decoration:
                      InputDecoration(
                        hintText:
                        _gpt.isLoaded
                            ? 'Ask anything...'
                            : 'Select a GGUF model first...',

                        border:
                        const OutlineInputBorder(),

                        contentPadding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),

                      onSubmitted: (_) {
                        if (!_generating) {
                          _sendMessage();
                        }
                      },
                    ),
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  // ============================================
                  // SEND / STOP
                  // ============================================

                  if (_generating)
                    IconButton.filled(
                      tooltip: 'Stop',

                      onPressed:
                      _stopGeneration,

                      icon: const Icon(
                        Icons.stop,
                      ),
                    )
                  else
                    IconButton.filled(
                      tooltip: 'Send',

                      onPressed:
                      _gpt.isLoaded
                          ? _sendMessage
                          : null,

                      icon: const Icon(
                        Icons.send,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
            ),

            const SizedBox(
              height: 16,
            ),

            Text(
              _gpt.isLoaded
                  ? 'AI Ready'
                  : 'Select a GGUF Model',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge,
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              _gpt.isLoaded
                  ? 'Ask anything to start chatting.'
                  : 'Select a local .gguf model file to start.',
              textAlign:
              TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CHAT MESSAGE
// ============================================================

class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.text,
  });

  final String role;

  String text;
}

// ============================================================
// MESSAGE BUBBLE
// ============================================================

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
  });

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser =
        message.role == 'user';

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,

      child: Container(
        constraints:
        const BoxConstraints(
          maxWidth: 700,
        ),

        margin: const EdgeInsets.only(
          bottom: 12,
        ),

        padding:
        const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),

        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context)
              .colorScheme
              .primaryContainer
              : Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,

          borderRadius:
          BorderRadius.circular(
            16,
          ),
        ),

        child: SelectableText(
          message.text,
        ),
      ),
    );
  }
}

// ============================================================
// THINKING BUBBLE
// ============================================================

class _ThinkingBubble
    extends StatelessWidget {
  const _ThinkingBubble({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
      Alignment.centerLeft,

      child: Container(
        constraints:
        const BoxConstraints(
          maxWidth: 700,
        ),

        margin: const EdgeInsets.only(
          bottom: 12,
        ),

        padding:
        const EdgeInsets.all(
          14,
        ),

        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,

          borderRadius:
          BorderRadius.circular(
            16,
          ),
        ),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .psychology_alt_outlined,
                  size: 18,
                ),

                SizedBox(
                  width: 6,
                ),

                Text(
                  'Thinking...',
                  style: TextStyle(
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 8,
            ),

            SelectableText(
              text,
            ),
          ],
        ),
      ),
    );
  }
}