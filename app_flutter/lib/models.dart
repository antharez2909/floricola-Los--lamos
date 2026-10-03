// ======================================================================
// MODELOS: las "formas" de datos que la app maneja
// ======================================================================
// Un "modelo" es una clase que representa un tipo de dato del backend
// (un usuario, un producto) usando tipos propios de Dart (String, int,
// double...) en vez de trabajar con Map<String, dynamic> sueltos por
// todos lados. Ventajas de esto:
//   - El editor avisa si se escribe mal un nombre de campo
//     (usuario.nombre en vez de usuario.nombres, por ejemplo).
//   - Toda la conversión "JSON -> Dart" queda en un solo lugar
//     (el factory fromJson de cada clase), en vez de repetirse
//     en cada pantalla que consume la API.

/// Representa un usuario (cliente o administrador) tal como lo devuelve
/// la API en /api/login, /api/registro, /api/me y /api/clientes.
class Usuario {
  Usuario({
    this.id,
    required this.usuario,
    required this.nombres,
    required this.apellidos,
    required this.correo,
    required this.rol,
    this.edad, // el único campo opcional: por eso no lleva "required"
    this.correoPendiente,
  });

  final int? id;
  final String usuario;
  final String nombres;
  final String apellidos;
  final String correo;
  final String rol; // "cliente" o "admin"
  final int? edad; // el "?" indica que puede no venir (nullable)
  final String? correoPendiente;

  /// Atajo para no escribir "rol == 'admin'" en cada pantalla.
  /// Se usa así: `if (usuario.esAdmin) { ... }`
  bool get esAdmin => rol == 'admin';

  /// Junta nombres y apellidos en un solo texto para mostrar en la UI.
  /// El .trim() al final evita un espacio de sobra si alguno viniera vacío.
  String get nombreCompleto => '$nombres $apellidos'.trim();

  /// La primera letra del nombre, en mayúscula, para los avatares
  /// circulares (por ejemplo "Ana" -> "A"). Si por algún motivo
  /// 'nombres' llega vacío, se usa '?' en vez de que la app truene
  /// al intentar leer nombres[0] de un texto vacío.
  String get inicial => nombres.isEmpty ? '?' : nombres[0].toUpperCase();

  /// Convierte el Map que llega de jsonDecode(...) (la respuesta JSON de
  /// la API, ya decodificada) en un objeto Usuario de verdad.
  ///
  /// El patrón `(json['campo'] ?? 'valor_por_defecto') as String` cubre
  /// el caso en que el servidor no mande ese campo (json['campo'] sería
  /// null): en vez de que la app truene, se usa un valor por defecto
  /// razonable.
  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: (json['id'] as num?)?.toInt(),
      usuario: (json['usuario'] ?? '') as String,
      nombres: (json['nombres'] ?? '') as String,
      apellidos: (json['apellidos'] ?? '') as String,
      correo: (json['correo'] ?? '') as String,
      rol: (json['rol'] ?? 'cliente') as String,
      // 'edad' puede llegar como int desde JSON, pero JSON en general no
      // distingue "int" de "double": por seguridad se lee como 'num'
      // (el tipo genérico que cubre ambos) y se convierte con .toInt().
      edad: (json['edad'] as num?)?.toInt(),
      correoPendiente: json['correo_pendiente'] as String?,
    );
  }
}

/// Una línea dentro de un carrito o de un pedido ya confirmado:
/// "2 unidades de Rosa a $2.00 cada una".
///
/// A diferencia de Usuario y Producto, esta clase no tiene un
/// 'fromJson': se usa tanto para lo que la app arma LOCALMENTE (el
/// carrito, antes de mandarlo al servidor) como para lo que la API
/// devuelve ya confirmado (el detalle de un pedido), así que cada lugar
/// que la necesita la construye a su manera (ver cart_service.dart y
/// Pedido.fromJson más abajo).
class LineaPedido {
  LineaPedido({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
  });

  final int productoId;
  final String nombre;
  final int cantidad;
  final double precioUnitario;

  /// cantidad * precioUnitario, redondeado a 2 decimales (como haría
  /// cualquier cálculo de dinero).
  double get subtotal =>
      double.parse((cantidad * precioUnitario).toStringAsFixed(2));
}

/// Un pedido ya confirmado, con sus líneas y su factura, tal como lo
// ignore: unintended_html_in_doc_comment
/// devuelve GET /api/pedidos/<id>. Para la lista (GET /api/pedidos) se
/// usa un Map simple en vez de esta clase, porque esa ruta no incluye
/// los items (ver PedidosScreen: la lista solo pide "más liviano" con
/// id/fecha/estado/total, y el detalle completo se pide aparte al tocar
/// un pedido).
class Pedido {
  Pedido({
    required this.id,
    required this.fecha,
    required this.estado,
    required this.estadoPago,
    required this.total,
    required this.items,
    required this.tieneComprobante,
    this.numeroFactura,
  });

  final int id;
  final DateTime fecha;
  final String
  estado; // "pendiente" | "listo_para_retiro" | "retirado" | "cancelado"
  final String
  estadoPago; // "pendiente" | "en_revision" | "confirmado" | "rechazado" (pago)
  final double total;
  final List<LineaPedido> items;
  final bool tieneComprobante;
  final String? numeroFactura;

  factory Pedido.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List<dynamic>? ?? []);
    final factura = json['factura'] as Map<String, dynamic>?;
    return Pedido(
      id: (json['id'] as num).toInt(),
      fecha: DateTime.parse(json['fecha'] as String),
      estado: (json['estado'] ?? 'pendiente') as String,
      estadoPago: (json['estado_pago'] ?? 'pendiente') as String,
      total: (json['total'] as num).toDouble(),
      items: itemsJson.map((e) {
        final m = e as Map<String, dynamic>;
        return LineaPedido(
          productoId: (m['producto_id'] as num).toInt(),
          nombre: m['nombre'] as String,
          cantidad: (m['cantidad'] as num).toInt(),
          precioUnitario: (m['precio_unitario'] as num).toDouble(),
        );
      }).toList(),
      tieneComprobante: (json['tiene_comprobante'] ?? false) as bool,
      numeroFactura: factura?['numero'] as String?,
    );
  }
}

/// Representa un producto del inventario, tal como lo devuelve la API
/// en /api/productos.
class Producto {
  Producto({
    required this.id,
    required this.nombre,
    required this.cantidad,
    required this.precio,
    required this.tamanoTalloCm,
    this.imagenUrl,
  });

  final int id;
  final String nombre;
  final int cantidad;
  final double precio;
  final int tamanoTalloCm; // largo del tallo, en centímetros
  final String? imagenUrl; // nombre/ruta de la imagen guardada en Flask

  /// Igual que Usuario.fromJson: transforma el Map crudo del backend
  /// en un objeto Producto con los tipos correctos de Dart.
  /// Aquí no hay valores por defecto porque un producto SIEMPRE debería
  /// traer estos campos (la API los garantiza); si alguno falta,
  /// es preferible que la conversión falle de forma ruidosa (un error
  /// claro) a que la app muestre un producto con datos inventados.
  factory Producto.fromJson(Map<String, dynamic> json) {
    final rawTallo = json['tamano_tallo_cm'];
    final rawImagen = json['imagen_url'];
    return Producto(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
      precio: (json['precio'] as num?)?.toDouble() ?? 0,
      tamanoTalloCm: (rawTallo as num?)?.toInt() ?? 40,
      imagenUrl: rawImagen is String && rawImagen.isNotEmpty ? rawImagen : null,
    );
  }
}
