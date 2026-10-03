// ======================================================================
// CARRITO DE COMPRAS
// ======================================================================
// El carrito se mantiene en memoria para reaccionar instantáneamente en la UI
// y también se persiste localmente por usuario con SharedPreferences. No es una
// fuente de verdad de precios o stock: al confirmar, el backend vuelve a validar
// todo contra MySQL.
//
// Es un singleton, como ApiService, para que CUALQUIER pantalla (la
// lista de productos, la pestaña de carrito, la barra de navegación con
// su contador) vea siempre el mismo carrito.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Una línea del carrito: un producto y cuántas unidades se quieren.
/// Se guarda el Producto completo (no solo su id) para poder mostrar su
/// nombre y precio en la pantalla de carrito sin tener que volver a
/// pedirlo al servidor.
class ItemCarrito {
  ItemCarrito({required this.producto, required this.cantidad});

  final Producto producto;
  int cantidad;

  double get subtotal => producto.precio * cantidad;
}

/// Servicio singleton que gestiona el estado del carrito de compras.
/// Mantiene los productos en memoria, sincroniza la persistencia local por usuario
/// mediante SharedPreferences y notifica cambios a la UI en tiempo real mediante ValueNotifier.
class CartService {
  CartService._();
  static final CartService instance = CartService._();

  final Map<int, ItemCarrito> _items = {}; // clave: producto.id
  String? _usuarioActual;

  String get _clavePersistencia => 'carrito_${Uri.encodeComponent(_usuarioActual ?? 'anonimo')}';

  /// Carga el carrito guardado para un usuario desde SharedPreferences.
  /// Se mantiene separado por correo para evitar que una persona vea
  /// el carrito de otra al cambiar de cuenta en el mismo teléfono.
  Future<void> cargarParaUsuario(String correo) async {
    _usuarioActual = correo.toLowerCase().trim();
    _items.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clavePersistencia);
    if (raw == null || raw.isEmpty) {
      _avisar();
      return;
    }
    try {
      final lista = jsonDecode(raw) as List<dynamic>;
      for (final entrada in lista) {
        final item = entrada as Map<String, dynamic>;
        final producto = Producto.fromJson(item['producto'] as Map<String, dynamic>);
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
        if (cantidad > 0) {
          _items[producto.id] = ItemCarrito(producto: producto, cantidad: cantidad);
        }
      }
    } catch (_) {
      await prefs.remove(_clavePersistencia);
    }
    _avisar();
  }

  /// Guarda el estado actual del carrito en el almacenamiento local del dispositivo.
  Future<void> _persistir() async {
    if (_usuarioActual == null) return;
    final prefs = await SharedPreferences.getInstance();
    final datos = _items.values.map((item) => {
      'producto': {
        'id': item.producto.id,
        'nombre': item.producto.nombre,
        'cantidad': item.producto.cantidad,
        'precio': item.producto.precio,
        'tamano_tallo_cm': item.producto.tamanoTalloCm,
        'imagen_url': item.producto.imagenUrl,
      },
      'cantidad': item.cantidad,
    }).toList();
    await prefs.setString(_clavePersistencia, jsonEncode(datos));
  }

  /// ValueNotifier envolviendo la lista de items: cualquier widget que
  /// lo escuche (ValueListenableBuilder) se redibuja solo cada vez que
  /// se agrega, quita o cambia la cantidad de algo en el carrito. Por
  /// ejemplo, el contador rojo sobre el ícono de carrito en la barra de
  /// navegación se actualiza así, sin que HomeScreen tenga que hacer
  /// nada especial.
  final ValueNotifier<List<ItemCarrito>> items = ValueNotifier<List<ItemCarrito>>([]);

  /// Devuelve la suma total de unidades acumuladas en el carrito.
  int get cantidadTotal => _items.values.fold(0, (suma, i) => suma + i.cantidad);

  /// Devuelve el monto total acumulado del carrito.
  double get total => _items.values.fold(0.0, (suma, i) => suma + i.subtotal);

  /// Indica si el carrito no tiene ningún producto.
  bool get estaVacio => _items.isEmpty;

  /// Agrega 'cantidad' unidades de un producto. Si ya estaba en el
  /// carrito, suma a lo que ya había en vez de duplicar la línea.
  void agregar(Producto producto, {int cantidad = 1}) {
    final actual = _items[producto.id];
    if (actual != null) {
      actual.cantidad += cantidad;
    } else {
      _items[producto.id] = ItemCarrito(producto: producto, cantidad: cantidad);
    }
    _avisar();
    _persistir();
  }

  /// Cambia la cantidad de una línea a un valor exacto. Si el resultado
  /// es 0 o menos, la línea se elimina del carrito directamente.
  void actualizarCantidad(int productoId, int cantidad) {
    if (cantidad <= 0) {
      quitar(productoId);
      return;
    }
    final actual = _items[productoId];
    if (actual != null) {
      actual.cantidad = cantidad;
      _avisar();
      _persistir();
    }
  }

  /// Elimina por completo un producto del carrito utilizando su ID.
  void quitar(int productoId) {
    _items.remove(productoId);
    _avisar();
    _persistir();
  }

  /// Limpia todos los elementos del carrito en memoria y en almacenamiento local.
  void vaciar() {
    _items.clear();
    _avisar();
    _persistir();
  }

  /// Convierte el carrito al formato exacto que espera
  /// POST /api/pedidos: { "items": [ {"producto_id": 1, "cantidad": 2}, ... ] }
  /// Nótese que NO se manda el precio: el servidor siempre vuelve a leer
  /// el precio real desde la base de datos (ver crear_pedido en api.py),
  /// así nadie puede manipular la app para pagar menos de lo que cuesta.
  Map<String, dynamic> aJsonParaPedido() {
    return {
      'items': _items.values
          .map((i) => {'producto_id': i.producto.id, 'cantidad': i.cantidad})
          .toList(),
    };
  }

  /// Notifica a los oyentes de ValueNotifier actualizando la lista expuesta.
  void _avisar() => items.value = _items.values.toList(growable: false);
}