// ======================================================================
// PANTALLA DE CARRITO Y CONFIRMACIÓN DE PEDIDO (checkout)
// ======================================================================
// Muestra lo que hay en CartService (ver cart_service.dart), permite
// ajustar cantidades o quitar productos, y al presionar "Confirmar
// pedido" manda todo el carrito de una sola vez a POST /api/pedidos
//
// Esta pantalla NO calcula el total "de verdad": lo que se ve aquí
// (CartService.instance.total) es solo un estimado para que la persona
// sepa cuánto va a pagar ANTES de confirmar. El total real, el que
// queda guardado, lo calcula el servidor a partir de los precios que
// tiene en la base de datos en ese momento (ver crear_pedido en api.py):
// así, si el precio de un producto cambiara justo en ese instante, o si
// alguien intentara manipular la app, el cobro real sigue siendo correcto.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../cart_service.dart';
import '../theme.dart';
import 'comprobante_screen.dart';

class CarritoScreen extends StatefulWidget {
  const CarritoScreen({super.key});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  bool _confirmando = false;

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Envía el carrito completo al servidor. Si todo sale bien, vacía el
  /// carrito local y pasa directo a la pantalla de pago por transferencia
  /// (datos bancarios + subir el comprobante), ya que es lo siguiente que
  /// la persona necesita hacer para que su pedido avance.
  Future<void> _confirmar() async {
    setState(() => _confirmando = true);
    try {
      final pedido = await ApiService.instance.crearPedido(
        CartService.instance.aJsonParaPedido(),
      );
      CartService.instance.vaciar();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ComprobanteScreen(pedidoId: pedido.id, total: pedido.total),
        ),
      );
      // CarritoScreen es una pestaña dentro de HomeScreen, no una ruta
      // independiente. Al regresar del pago permanece en la pestaña Carrito
      // vacía; cerrar esta ruta también cerraría HomeScreen y dejaría la app
      // sin una pantalla visible.
    } on ApiException catch (e) {
      // Casos típicos aquí: el backend descubrió que, entre que se armó
      // el carrito y se confirmó, uno de los productos se quedó sin
      // stock (por ejemplo, otra persona compró la última unidad antes).
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carrito')),
      // ValueListenableBuilder redibuja esta pantalla automáticamente
      // cada vez que CartService.instance.items cambia (agregar, quitar,
      // o cambiar una cantidad), sin necesidad de un setState manual aquí.
      body: ValueListenableBuilder<List<ItemCarrito>>(
        valueListenable: CartService.instance.items,
        builder: (context, items, _) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 40,
                      color: AppColors.inkMuted,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Tu carrito está vacío',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Agrega productos desde el catálogo.',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: items.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.producto.nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${item.producto.precio.toStringAsFixed(2)} c/u',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Selector de cantidad: "-" [n] "+"
                            _BotonCantidad(
                              icono: Icons.remove,
                              onPressed: () =>
                                  CartService.instance.actualizarCantidad(
                                    item.producto.id,
                                    item.cantidad - 1,
                                  ),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${item.cantidad}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _BotonCantidad(
                              icono: Icons.add,
                              onPressed: () {
                                // No se deja pedir más unidades de las que
                                // hay en stock: es una validación "amable"
                                // en el celular; el servidor la vuelve a
                                // hacer de todas formas al confirmar.
                                if (item.cantidad >= item.producto.cantidad) {
                                  _aviso('No hay más stock disponible');
                                  return;
                                }
                                CartService.instance.actualizarCantidad(
                                  item.producto.id,
                                  item.cantidad + 1,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: Text(
                                '\$${item.subtotal.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Quitar',
                              icon: const Icon(Icons.close, size: 18),
                              color: AppColors.inkMuted,
                              onPressed: () =>
                                  CartService.instance.quitar(item.producto.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Resumen y botón de confirmar, fijos abajo (fuera del scroll).
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.hairline)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total estimado',
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                        Text(
                          '\$${CartService.instance.total.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _confirmando ? null : _confirmar,
                      child: _confirmando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Confirmar pedido'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Botoncito circular "-" o "+" para el selector de cantidad del carrito.
class _BotonCantidad extends StatelessWidget {
  const _BotonCantidad({required this.icono, required this.onPressed});

  final IconData icono;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Icon(icono, size: 14, color: AppColors.forest),
      ),
    );
  }
}
