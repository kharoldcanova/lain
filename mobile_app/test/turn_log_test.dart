import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/diagnostics/turn_log.dart';

void main() {
  late Directory dir;
  late TurnLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lain-turns-');
    log = TurnLog(directory: () async => dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('sin archivo devuelve una lista vacía', () async {
    expect(await log.read(), isEmpty);
  });

  test('añade y lee turnos en orden, sobreviviendo a reaperturas', () async {
    await log.append(<String, Object?>{'ts': 'uno', 'ttft_ms': 100});
    await log.append(<String, Object?>{'ts': 'dos', 'ttft_ms': 200});

    final reabierto = TurnLog(directory: () async => dir);
    final turns = await reabierto.read();

    expect(turns, hasLength(2));
    expect(turns.first['ts'], 'uno');
    expect(turns.last['ttft_ms'], 200);
  });

  test('ignora líneas corruptas sin perder las válidas', () async {
    final file = File('${dir.path}/${TurnLog.fileName}')
      ..writeAsStringSync('{"ts":"ok"}\n{roto\n');
    expect(file.existsSync(), isTrue);

    await log.append(<String, Object?>{'ts': 'nuevo'});
    final turns = await log.read();

    expect(turns.map((turn) => turn['ts']), <String>['ok', 'nuevo']);
  });

  test('respeta el límite devolviendo los últimos', () async {
    for (var i = 0; i < 8; i++) {
      await log.append(<String, Object?>{'ts': '$i'});
    }

    final turns = await log.read(limit: 3);

    expect(turns.map((turn) => turn['ts']), <String>['5', '6', '7']);
  });

  test('clear borra solo el registro', () async {
    await log.append(<String, Object?>{'ts': 'uno'});
    final otro = File('${dir.path}/lain.db')..writeAsStringSync('recuerdos');

    await log.clear();

    expect(await log.read(), isEmpty);
    expect(otro.readAsStringSync(), 'recuerdos');
  });

  test('un fallo de escritura no lanza (instrumentación best-effort)', () async {
    final logRoto = TurnLog(directory: () async => throw const FileSystemException('sin disco'));

    await expectLater(logRoto.append(<String, Object?>{'ts': 'x'}), completes);
    expect(await logRoto.read(), isEmpty);
  });

  test('summarizeTurns exige muestras mínimas y calcula mediana y p90', () {
    final turns = <Map<String, Object?>>[
      for (var i = 1; i <= 10; i++)
        <String, Object?>{
          'ttft_ms': i * 100,
          'total_ms': i * 1000,
          'tok_per_s': i.toDouble(),
        },
    ];

    final stats = summarizeTurns(turns);

    expect(stats.count, 10);
    expect(stats.ttftMs!.count, 10);
    // 1..10 -> mediana 5.5 -> 550 ms; p90 nearest-rank (9.º) -> 900 ms.
    expect(stats.ttftMs!.median, 550);
    expect(stats.ttftMs!.p90, 900);
    expect(stats.tokensPerSecond!.median, 5.5);
    expect(stats.prefillMs, isNull);
  });

  test('con menos de 5 muestras no se publican percentiles', () {
    final stats = summarizeTurns(<Map<String, Object?>>[
      <String, Object?>{'ttft_ms': 100},
      <String, Object?>{'ttft_ms': 200},
    ]);

    expect(stats.count, 2);
    expect(stats.ttftMs, isNull);
  });
}
