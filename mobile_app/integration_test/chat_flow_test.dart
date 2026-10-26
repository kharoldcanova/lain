import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lain_mobile/app.dart';
import 'package:lain_mobile/domain/chat/chat_state.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';

/// Flujo completo en dispositivo real: la app arranca, carga el GGUF del
/// almacenamiento externo, recibe un mensaje y muestra la respuesta generada.
///
///   flutter test integration_test/chat_flow_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la UI responde con el modelo local', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LainApp()));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LainApp)),
    );

    Future<void> until(bool Function() condition, Duration timeout) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        if (condition()) return;
      }
      fail('tiempo agotado; estado=${container.read(chatControllerProvider).status}');
    }

    await until(
      () => container.read(chatControllerProvider).status == EngineStatus.ready,
      const Duration(minutes: 3),
    );

    await tester.enterText(find.byType(TextField), 'Hola LAIN, ¿quién eres?');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    await until(
      () {
        final state = container.read(chatControllerProvider);
        return !state.generating && state.messages.length >= 2;
      },
      const Duration(minutes: 3),
    );

    final answer = container.read(chatControllerProvider).messages.last.text;
    // ignore: avoid_print
    print('RESPUESTA UI: $answer');

    expect(answer, isNotEmpty);
    expect(answer, isNot(contains('No pude responder')));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
