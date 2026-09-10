import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  test('LocalLlmConfig default values are correct', () {
    const config = LocalLlmConfig();

    expect(config.threads, 4);
    expect(config.contextSize, 4096);
    expect(config.maxTokens, 384);
    expect(config.temperature, 0.60);
  });
}