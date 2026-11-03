import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` solo cuando la app se compila con
/// `--dart-define=LAIN_EXPERIMENTAL=true`.
///
/// Hasta que existan los flavors de Gradle (F4), este compile-time flag es lo
/// que separa la build experimental de la de producción: sin él, la pantalla
/// de diagnóstico y el registro de turnos quedan deshabilitados.
const bool lainExperimentalBuild = bool.fromEnvironment('LAIN_EXPERIMENTAL');

/// Nombre del flavor con el que se compiló la app (`prod` o `experimental`).
///
/// Se pasa explícitamente con `--dart-define`; Gradle no lo inyecta solo.
const String lainFlavorName = String.fromEnvironment('LAIN_FLAVOR', defaultValue: 'prod');

/// Indica si la app corre en modo experimental. Inyectable en pruebas.
final experimentalModeProvider = Provider<bool>((ref) => lainExperimentalBuild);
