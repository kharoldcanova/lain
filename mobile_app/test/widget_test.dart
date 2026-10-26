import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/app.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';

void main() {
  testWidgets('la pantalla de chat arranca vacía', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LainApp()));

    expect(find.text('Estoy aquí.'), findsOneWidget);
    expect(find.text('Escribe un mensaje…'), findsOneWidget);
  });

  testWidgets('enviar un mensaje añade el turno del usuario', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LainApp()));

    await tester.enterText(find.byType(TextField), 'Hola, LAIN');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Hola, LAIN'), findsOneWidget);
    expect(find.text('Estoy aquí.'), findsNothing);
  });

  test('el controlador ignora mensajes vacíos', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(chatControllerProvider.notifier).send('   ');

    expect(container.read(chatControllerProvider), isEmpty);
  });
}
