import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/lain_native.dart';

void main() {
  test('LainMetrics tiene el layout acordado con el puente (64 bytes)', () {
    expect(sizeOf<LainMetrics>(), 64);
  });

  test('LainTurnMetrics calcula tok/s y serializa al JSONL', () {
    const metrics = LainTurnMetrics(
      loadMs: 5000,
      prefillMs: 1800,
      decodeMs: 2000,
      ttftMs: 2100,
      nPromptTokens: 500,
      nGeneratedTokens: 40,
      nThreads: 4,
      nBatchThreads: 4,
      nCtx: 2048,
      loadMode: -1,
      nBackend: 1,
      instrumented: true,
    );

    expect(metrics.tokensPerSecond, 20.0);
    final json = metrics.toJson();
    expect(json['ttft_ms'], 2100);
    expect(json['n_prompt'], 500);
    expect(json['n_generated'], 40);
    expect(json['tok_per_s'], 20.0);
    expect(json['instrumented'], isTrue);
  });

  test('LainTurnMetrics.fromJson sobrevive a campos ausentes', () {
    final metrics = LainTurnMetrics.fromJson(<String, Object?>{
      'ttft_ms': 1200,
    });

    expect(metrics.ttftMs, 1200);
    expect(metrics.nGeneratedTokens, 0);
    expect(metrics.tokensPerSecond, 0);
    expect(metrics.instrumented, isFalse);
  });
}
