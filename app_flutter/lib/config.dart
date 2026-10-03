// ======================================================================
// CONFIGURACIÓN GLOBAL DE LA APP
// ======================================================================

import 'package:flutter/foundation.dart';

/// Agrupa la configuración global de la app.
class Config {
  static const _apiBaseUrlConfigurada = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get apiBaseUrl {
    if (_apiBaseUrlConfigurada.isNotEmpty) {
      return _apiBaseUrlConfigurada;
    }
    if (kIsWeb) {
      return 'http://localhost:5000';
    }
    // Si estás usando el emulador de Android, usa 10.0.2.2 automáticamente.
    // En un celular físico, compila con --dart-define=API_BASE_URL=http://<IP-del-PC>:5000.
    return 'http://10.0.2.2:5000';
  }
}

/// Variable global de compatibilidad.
const String baseUrl = 'http://10.0.2.2:5000';
