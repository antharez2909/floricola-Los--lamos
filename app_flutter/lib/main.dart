// ======================================================================
// PUNTO DE ENTRADA DE LA APP
// ======================================================================

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'api_service.dart';
import 'models.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

/// Función que Flutter ejecuta primero.
/// runApp() monta el widget raíz de toda la interfaz.
void main() => runApp(const FloricolaApp());

/// Widget raíz de la aplicación.
class FloricolaApp extends StatelessWidget {
  const FloricolaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Florícola Los Álamos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) => AppBackgroundLayer(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthGate(),
    );
  }
}

/// Decide qué pantalla mostrar según exista una sesión guardada.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _inicio = ApiService.instance.cargarSesion();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _inicio,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return ValueListenableBuilder<Usuario?>(
          valueListenable: ApiService.instance.sesion,
          builder: (context, usuario, _) {
            if (usuario == null) {
              return const LoginScreen();
            }

            return HomeScreen(usuario: usuario);
          },
        );
      },
    );
  }
}
