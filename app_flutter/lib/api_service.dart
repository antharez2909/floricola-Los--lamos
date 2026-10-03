// ======================================================================
// SERVICIO DE API: todo lo que habla HTTP con el servidor Flask
// ======================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_background.dart';
import 'config.dart';
import 'models.dart';
import 'cart_service.dart';

/// Resultado de cualquier lista paginada del backend.
class PaginaDe<T> {
  PaginaDe({required this.datos, required this.total});

  final List<T> datos;
  final int total;
}

/// Error de la API.
class ApiException implements Exception {
  ApiException(this.mensaje, {this.codigo});

  final String mensaje;
  final int? codigo;

  @override
  String toString() => mensaje;
}

/// Singleton para consumir la API de Flask.
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  static const _claveToken = 'token';
  String? _token;

  final ValueNotifier<Usuario?> sesion = ValueNotifier<Usuario?>(null);

  // ====================================================================
  // SESIÓN
  // ====================================================================

  Future<void> cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_claveToken);

    if (_token == null) return;

    try {
      final data = await _enviar('GET', '/api/me') as Map<String, dynamic>;

      sesion.value = Usuario.fromJson(data);

      await CartService.instance.cargarParaUsuario(sesion.value!.correo);
    } on ApiException {
      await cerrarSesion();
    } catch (e) {
      debugPrint('Error al cargar sesión: $e');
      await cerrarSesion();
    }
  }

  Future<void> iniciarSesion(String correo, String password) async {
    final data = await _enviar(
      'POST',
      '/api/login',
      cuerpo: {'correo': correo, 'password': password},
      conToken: false,
    ) as Map<String, dynamic>;

    final token = data['token'];

    if (token is! String || token.isEmpty) {
      throw ApiException('El servidor no devolvió un token de sesión.');
    }

    final usuario = data['usuario'];

    if (usuario is! Map<String, dynamic>) {
      throw ApiException('El servidor no devolvió los datos del usuario.');
    }

    _token = token;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveToken, _token!);

    sesion.value = Usuario.fromJson(usuario);

    await CartService.instance.cargarParaUsuario(sesion.value!.correo);
  }

  Future<String> solicitarRecuperacionPassword(String correo) async {
    final data = await _enviar(
      'POST',
      '/api/password/recuperar',
      cuerpo: {'correo': correo},
      conToken: false,
    ) as Map<String, dynamic>;
    final mensaje = data['mensaje'];
    if (mensaje is! String || mensaje.isEmpty) {
      throw ApiException('El servidor no confirmó la solicitud.');
    }
    return mensaje;
  }

  Future<void> restablecerPassword({
    required String correo,
    required String codigo,
    required String nuevaPassword,
  }) async {
    await _enviar(
      'POST',
      '/api/password/restablecer',
      cuerpo: {
        'correo': correo,
        'codigo': codigo,
        'nueva_password': nuevaPassword,
      },
      conToken: false,
    );
  }

  Future<void> registrar({
    required String nombres,
    required String apellidos,
    required String correo,
    required String password,
    required int edad,
  }) async {
    await _enviar(
      'POST',
      '/api/registro',
      cuerpo: {
        'nombres': nombres,
        'apellidos': apellidos,
        'correo': correo,
        'password': password,
        'edad': edad,
      },
      conToken: false,
    );
  }

  Future<void> verificarCorreo(String correo, String codigo) async {
    final data = await _enviar(
      'POST',
      '/api/verificar-email',
      cuerpo: {'correo': correo, 'codigo': codigo},
    );
    if (data is Map<String, dynamic> &&
        data['token'] is String &&
        data['usuario'] is Map<String, dynamic>) {
      _token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveToken, _token!);
      sesion.value = Usuario.fromJson(data['usuario'] as Map<String, dynamic>);
      await CartService.instance.cargarParaUsuario(sesion.value!.correo);
    }
  }

  Future<void> reenviarCodigoVerificacion(String correo) async {
    await _enviar(
      'POST',
      '/api/reenviar-verificacion',
      cuerpo: {'correo': correo},
      conToken: false,
    );
  }

  Future<void> cerrarSesion() async {
    _token = null;
    AppBackground.imageUrl.value = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveToken);

    CartService.instance.vaciar();
    sesion.value = null;
  }

  // ====================================================================
  // PRODUCTOS
  // ====================================================================

  Future<PaginaDe<Producto>> productos({
    int pagina = 1,
    int porPagina = 20,
    String? buscar,
  }) async {
    final parametros = {
      'pagina': '$pagina',
      'por_pagina': '$porPagina',
      if (buscar != null && buscar.isNotEmpty) 'buscar': buscar,
    };

    final ruta = Uri(
      path: '/api/productos',
      queryParameters: parametros,
    ).toString();

    final data = await _enviar('GET', ruta) as Map<String, dynamic>;

    final datos = data['datos'];

    if (datos is! List) {
      throw ApiException(
        'El servidor devolvió un formato inválido para productos.',
      );
    }

    final lista = datos
        .map((e) => Producto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final total = data['total'];

    if (total is! num) {
      throw ApiException('El servidor no devolvió el total de productos.');
    }

    return PaginaDe(datos: lista, total: total.toInt());
  }

  Future<void> actualizarProducto({
    required int id,
    required String nombre,
    required int cantidad,
    required double precio,
    required int tamanoTalloCm,
    List<int>? imagenBytes,
    String? nombreArchivo,
  }) async {
    if (imagenBytes == null) {
      await _enviar(
        'PUT',
        '/api/productos/$id',
        cuerpo: {
          'nombre': nombre,
          'cantidad': cantidad,
          'precio': precio,
          'tamano_tallo_cm': tamanoTalloCm,
        },
      );

      return;
    }

    await _enviarProductoMultipart(
      metodo: 'PUT',
      ruta: '/api/productos/$id',
      nombre: nombre,
      cantidad: cantidad,
      precio: precio,
      tamanoTalloCm: tamanoTalloCm,
      imagenBytes: imagenBytes,
      nombreArchivo: nombreArchivo ?? 'producto.jpg',
    );
  }

  Future<void> agregarProducto({
    required String nombre,
    required int cantidad,
    required double precio,
    required int tamanoTalloCm,
    List<int>? imagenBytes,
    String? nombreArchivo,
  }) async {
    if (imagenBytes == null) {
      await _enviar(
        'POST',
        '/api/productos',
        cuerpo: {
          'nombre': nombre,
          'cantidad': cantidad,
          'precio': precio,
          'tamano_tallo_cm': tamanoTalloCm,
        },
      );

      return;
    }

    await _enviarProductoMultipart(
      metodo: 'POST',
      ruta: '/api/productos',
      nombre: nombre,
      cantidad: cantidad,
      precio: precio,
      tamanoTalloCm: tamanoTalloCm,
      imagenBytes: imagenBytes,
      nombreArchivo: nombreArchivo ?? 'producto.jpg',
    );
  }

  Future<void> eliminarProducto(int id) async {
    await _enviar('DELETE', '/api/productos/$id');
  }

  // ====================================================================
  // CLIENTES
  // ====================================================================

  Future<PaginaDe<Usuario>> clientes({
    int pagina = 1,
    int porPagina = 20,
    String? buscar,
  }) async {
    final parametros = {
      'pagina': '$pagina',
      'por_pagina': '$porPagina',
      if (buscar != null && buscar.isNotEmpty) 'buscar': buscar,
    };

    final ruta = Uri(
      path: '/api/clientes',
      queryParameters: parametros,
    ).toString();

    final data = await _enviar('GET', ruta) as Map<String, dynamic>;

    final datos = data['datos'];

    if (datos is! List) {
      throw ApiException(
        'El servidor devolvió un formato inválido para clientes.',
      );
    }

    final lista = datos
        .map((e) => Usuario.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final total = data['total'];

    if (total is! num) {
      throw ApiException('El servidor no devolvió el total de clientes.');
    }

    return PaginaDe(datos: lista, total: total.toInt());
  }

  Future<String?> actualizarMiPerfil(Map<String, dynamic> cambios) async {
    final data = await _enviar(
      'PUT',
      '/api/me',
      cuerpo: cambios,
    ) as Map<String, dynamic>;
    final usuario = data['usuario'];
    if (usuario is! Map<String, dynamic>) {
      throw ApiException('El servidor no devolvió el perfil actualizado.');
    }
    sesion.value = Usuario.fromJson(usuario);
    return data['correo_pendiente'] as String?;
  }

  Future<String?> actualizarCliente(
    int usuarioId,
    Map<String, dynamic> cambios,
  ) async {
    final data = await _enviar(
      'PUT',
      '/api/clientes/$usuarioId',
      cuerpo: cambios,
    ) as Map<String, dynamic>;
    return data['correo_pendiente'] as String?;
  }

  // ====================================================================
  // PEDIDOS Y FACTURAS
  // ====================================================================

  Future<Pedido> crearPedido(Map<String, dynamic> cuerpo) async {
    final data = await _enviar(
      'POST',
      '/api/pedidos',
      cuerpo: cuerpo,
    ) as Map<String, dynamic>;

    return Pedido.fromJson(data);
  }

  Future<PaginaDe<Map<String, dynamic>>> pedidos({
    int pagina = 1,
    int porPagina = 20,
    String? estado,
  }) async {
    final parametros = {
      'pagina': '$pagina',
      'por_pagina': '$porPagina',
      if (estado != null && estado.isNotEmpty) 'estado': estado,
    };

    final ruta = Uri(
      path: '/api/pedidos',
      queryParameters: parametros,
    ).toString();

    final data = await _enviar('GET', ruta) as Map<String, dynamic>;

    final datos = data['datos'];

    if (datos is! List) {
      throw ApiException(
        'El servidor devolvió un formato inválido para pedidos.',
      );
    }

    final lista = datos
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final total = data['total'];

    if (total is! num) {
      throw ApiException('El servidor no devolvió el total de pedidos.');
    }

    return PaginaDe(datos: lista, total: total.toInt());
  }

  Future<Pedido> detallePedido(int id) async {
    final data =
        await _enviar('GET', '/api/pedidos/$id') as Map<String, dynamic>;

    return Pedido.fromJson(data);
  }

  Future<void> actualizarEstadoPedido(int id, String estado) async {
    await _enviar('PUT', '/api/pedidos/$id/estado', cuerpo: {'estado': estado});
  }

  Future<void> eliminarPedido(int id) async {
    await _enviar('DELETE', '/api/pedidos/$id');
  }

  Future<void> subirComprobante({
    required int pedidoId,
    required List<int> imagenBytes,
    required String nombreArchivo,
  }) async {
    final uri = Uri.parse(
      '${Config.apiBaseUrl}/api/pedidos/$pedidoId/comprobante',
    );

    final req = http.MultipartRequest('POST', uri);

    req.headers['Accept'] = 'application/json';

    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }

    req.files.add(
      http.MultipartFile.fromBytes(
        'imagen',
        imagenBytes,
        filename: nombreArchivo,
      ),
    );

    final sinConexion = ApiException(
      'No se pudo conectar con el servidor '
      '(${Config.apiBaseUrl}). Revisa que Flask esté corriendo '
      'y la dirección sea correcta.',
    );

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 20));

      final res = await http.Response.fromStream(streamed);

      if (res.statusCode >= 400) {
        String mensaje = 'Error del servidor (${res.statusCode}).';

        try {
          final data = jsonDecode(utf8.decode(res.bodyBytes));

          if (data is Map && data['error'] is String) {
            mensaje = data['error'] as String;
          }
        } on FormatException catch (e) {
          debugPrint('Respuesta JSON inválida: $e');
        }

        throw ApiException(mensaje, codigo: res.statusCode);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('Error al subir comprobante: $e');
      throw sinConexion;
    }
  }

  Future<Uint8List> comprobante(int pedidoId) async {
    final uri = Uri.parse(
      '${Config.apiBaseUrl}/api/pedidos/$pedidoId/comprobante',
    );

    final headers = <String, String>{
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final sinConexion = ApiException(
      'No se pudo conectar con el servidor '
      '(${Config.apiBaseUrl}).',
    );

    try {
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode >= 400) {
        throw ApiException(
          'No se pudo cargar el comprobante '
          '(${res.statusCode}).',
          codigo: res.statusCode,
        );
      }

      return res.bodyBytes;
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('Error al cargar comprobante: $e');
      throw sinConexion;
    }
  }

  Future<void> revisarPago(int pedidoId, {required bool confirmar}) async {
    await _enviar(
      'PUT',
      '/api/pedidos/$pedidoId/pago',
      cuerpo: {'accion': confirmar ? 'confirmar' : 'rechazar'},
    );
  }

  // ====================================================================
  // CONTENIDO DE INICIO
  // ====================================================================

  Future<Map<String, dynamic>> contenidoInicio() async {
    final data =
        await _enviar('GET', '/api/inicio/contenido') as Map<String, dynamic>;
    final galeria = data['galeria'];
    if (galeria is! List || galeria.any((imagen) => imagen is! String)) {
      throw ApiException('El servidor devolvió una galería inválida.');
    }
    return data;
  }

  Future<void> subirFondoInicio({
    required List<int> imagenBytes,
    required String nombreArchivo,
  }) async {
    await _enviarImagenInicio(
      '/api/inicio/fondo',
      imagenBytes: imagenBytes,
      nombreArchivo: nombreArchivo,
    );
  }

  Future<void> quitarFondoInicio() async {
    await _enviar('DELETE', '/api/inicio/fondo');
  }

  Future<void> agregarImagenInicio({
    required List<int> imagenBytes,
    required String nombreArchivo,
  }) async {
    await _enviarImagenInicio(
      '/api/inicio/galeria',
      imagenBytes: imagenBytes,
      nombreArchivo: nombreArchivo,
    );
  }

  Future<void> quitarImagenInicio(String nombreArchivo) async {
    await _enviar(
      'DELETE',
      '/api/inicio/galeria/${Uri.encodeComponent(nombreArchivo)}',
    );
  }

  Future<void> _enviarImagenInicio(
    String ruta, {
    required List<int> imagenBytes,
    required String nombreArchivo,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.apiBaseUrl}$ruta'),
    );
    req.headers['Accept'] = 'application/json';
    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }
    req.files.add(
      http.MultipartFile.fromBytes(
        'imagen',
        imagenBytes,
        filename: nombreArchivo,
      ),
    );

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 20));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 400) {
        String mensaje = 'Error del servidor (${res.statusCode}).';
        try {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data is Map && data['error'] is String) {
            mensaje = data['error'] as String;
          }
        } on FormatException catch (e) {
          debugPrint('Respuesta JSON inválida: $e');
        }
        throw ApiException(mensaje, codigo: res.statusCode);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('Error al subir imagen de inicio: $e');
      throw ApiException(
        'No se pudo conectar con el servidor (${Config.apiBaseUrl}).',
      );
    }
  }

  // ====================================================================
  // MULTIPART PRODUCTOS
  // ====================================================================

  Future<void> _enviarProductoMultipart({
    required String metodo,
    required String ruta,
    required String nombre,
    required int cantidad,
    required double precio,
    required int tamanoTalloCm,
    required List<int> imagenBytes,
    required String nombreArchivo,
  }) async {
    final req = http.MultipartRequest(
      metodo,
      Uri.parse('${Config.apiBaseUrl}$ruta'),
    );

    req.headers['Accept'] = 'application/json';

    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }

    req.fields.addAll({
      'nombre': nombre,
      'cantidad': cantidad.toString(),
      'precio': precio.toString(),
      'tamano_tallo_cm': tamanoTalloCm.toString(),
    });

    req.files.add(
      http.MultipartFile.fromBytes(
        'imagen',
        imagenBytes,
        filename: nombreArchivo,
      ),
    );

    final sinConexion = ApiException(
      'No se pudo conectar con el servidor '
      '(${Config.apiBaseUrl}). Revisa que Flask esté corriendo '
      'y la dirección sea correcta.',
    );

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 20));

      final res = await http.Response.fromStream(streamed);

      if (res.statusCode >= 400) {
        String mensaje = 'Error del servidor (${res.statusCode}).';

        try {
          final data = jsonDecode(utf8.decode(res.bodyBytes));

          if (data is Map && data['error'] is String) {
            mensaje = data['error'] as String;
          }
        } on FormatException catch (e) {
          debugPrint('Respuesta JSON inválida: $e');
        }

        throw ApiException(mensaje, codigo: res.statusCode);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('Error en petición multipart: $e');
      throw sinConexion;
    }
  }

  // ====================================================================
  // IMÁGENES
  // ====================================================================

  String? urlImagenProducto(String? imagenUrl) {
    if (imagenUrl == null || imagenUrl.isEmpty) {
      return null;
    }

    if (imagenUrl.startsWith('http://') || imagenUrl.startsWith('https://')) {
      return imagenUrl;
    }

    return '${Config.apiBaseUrl}/api/productos/imagenes/'
        '${Uri.encodeComponent(imagenUrl)}';
  }

  String? urlImagenInicio(String? nombreArchivo) {
    if (nombreArchivo == null || nombreArchivo.isEmpty) {
      return null;
    }
    return '${Config.apiBaseUrl}/api/inicio/imagenes/'
        '${Uri.encodeComponent(nombreArchivo)}';
  }

  // ====================================================================
  // MOTOR HTTP INTERNO
  // ====================================================================

  Future<dynamic> _enviar(
    String metodo,
    String ruta, {
    Map<String, dynamic>? cuerpo,
    bool conToken = true,
  }) async {
    final req = http.Request(metodo, Uri.parse('${Config.apiBaseUrl}$ruta'));

    req.headers['Content-Type'] = 'application/json';
    req.headers['Accept'] = 'application/json';

    if (conToken && _token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }

    if (cuerpo != null) {
      req.body = jsonEncode(cuerpo);
    }

    final sinConexion = ApiException(
      'No se pudo conectar con el servidor '
      '(${Config.apiBaseUrl}). Revisa que Flask esté corriendo '
      'y la dirección sea correcta.',
    );

    http.Response res;

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 12));

      res = await http.Response.fromStream(streamed);
    } catch (e) {
      debugPrint('Error de conexión: $e');
      throw sinConexion;
    }

    dynamic data;

    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException catch (e) {
        debugPrint('Respuesta JSON inválida: $e');

        throw ApiException(
          'Respuesta inesperada del servidor '
          '(${res.statusCode}).',
          codigo: res.statusCode,
        );
      }
    }

    if (res.statusCode >= 400) {
      final mensaje = (data is Map && data['error'] is String)
          ? data['error'] as String
          : 'Error del servidor (${res.statusCode}).';

      if (res.statusCode == 401 && conToken) {
        await cerrarSesion();
      }

      throw ApiException(mensaje, codigo: res.statusCode);
    }

    return data;
  }
}
