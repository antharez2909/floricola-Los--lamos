import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Usamos importaciones relativas para evitar fallas con el nombre del paquete
import 'package:app_flutter/cart_service.dart';
import 'package:app_flutter/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CartService.instance.vaciar();
    await CartService.instance.cargarParaUsuario('prueba@example.com');
  });

  test('agrega productos y genera el contrato del pedido sin precios', () {
    final producto = Producto(
      id: 1,
      nombre: 'Girasol',
      cantidad: 20,
      precio: 1.50,
      tamanoTalloCm: 60,
    );

    CartService.instance.agregar(producto, cantidad: 2);
    CartService.instance.agregar(producto, cantidad: 3);
    final json = CartService.instance.aJsonParaPedido();

    expect(json['items'], [
      {'producto_id': 1, 'cantidad': 5},
    ]);
  });

  test('actualizar cantidad elimina cuando llega a cero', () {
    final producto = Producto(
      id: 2,
      nombre: 'Rosa',
      cantidad: 10,
      precio: 2,
      tamanoTalloCm: 50,
    );

    CartService.instance.agregar(producto);
    CartService.instance.actualizarCantidad(2, 0);

    expect(CartService.instance.estaVacio, isTrue);
  });
}
