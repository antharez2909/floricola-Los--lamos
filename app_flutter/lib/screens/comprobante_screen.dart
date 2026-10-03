// ======================================================================
// PANTALLA: datos bancarios y subida del comprobante de transferencia
// ======================================================================
// Se abre justo después de confirmar un pedido (ver carrito_screen.dart),
// y también se puede volver a abrir desde el detalle de un pedido si el
// admin rechazó un comprobante anterior y hay que subir uno nuevo.
//
// Flujo: la persona transfiere el dinero a la cuenta mostrada aquí fuera
// de la app (desde su banco), toma una foto o captura de pantalla del
// comprobante, la selecciona con el botón de abajo, y la sube. A partir
// de ahí el pedido queda "en revisión" hasta que el admin la confirme o
// la rechace (ver pedidos_screens.dart, DetallePedidoScreen).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../theme.dart';

/// Datos de la cuenta bancaria a donde debe transferir el cliente.
///
/// El titular se configura al compilar con --dart-define=
/// BANK_ACCOUNT_HOLDER=Nombre%20del%20titular, para no dejar un nombre
/// ficticio dentro del código fuente.
class _DatosBancarios {
  static const banco = 'Banco Pichincha';
  static const tipoCuenta = 'Cuenta de Ahorros';
  static const numero = '2211272796';
  static const titular = String.fromEnvironment(
    'BANK_ACCOUNT_HOLDER',
    defaultValue: 'Edison Stiven Remache Cuello',
  );
  static const ci = '0606132579';
}

class ComprobanteScreen extends StatefulWidget {
  const ComprobanteScreen({
    super.key,
    required this.pedidoId,
    required this.total,
  });

  final int pedidoId;
  final double total;

  @override
  State<ComprobanteScreen> createState() => _ComprobanteScreenState();
}

class _ComprobanteScreenState extends State<ComprobanteScreen> {
  XFile? _imagenElegida;
  Uint8List? _imagenBytes;
  bool _subiendo = false;

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Abre la galería del teléfono para elegir una imagen ya tomada.
  /// Se usa la galería (no la cámara) a propósito: así no hace falta
  /// pedir el permiso de cámara, y cubre tanto una foto recién tomada
  /// como una captura de pantalla de la app del banco.
  Future<void> _elegirImagen() async {
    try {
      final imagen = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600, // evita subir fotos de 12 MB sin necesidad
        imageQuality: 85,
      );
      if (imagen == null) return;
      final bytes = await imagen.readAsBytes();
      if (mounted) {
        setState(() {
          _imagenElegida = imagen;
          _imagenBytes = bytes;
        });
      }
    } catch (e) {
      _aviso('No se pudo abrir la galería');
    }
  }

  Future<void> _subir() async {
    final imagen = _imagenElegida;
    if (imagen == null) {
      _aviso('Primero selecciona una imagen');
      return;
    }

    setState(() => _subiendo = true);
    try {
      final bytes = _imagenBytes ?? await imagen.readAsBytes();
      await ApiService.instance.subirComprobante(
        pedidoId: widget.pedidoId,
        imagenBytes: bytes,
        nombreArchivo: imagen.name,
      );
      if (mounted) {
        _aviso(
          'Comprobante enviado. Te avisaremos cuando se confirme el pago.',
        );
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pagar por transferencia')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total a transferir',
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                      Text(
                        '\$${widget.total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Datos de la cuenta',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                _FilaDato(etiqueta: 'Banco', valor: _DatosBancarios.banco),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _FilaDato(
                  etiqueta: 'Tipo de cuenta',
                  valor: _DatosBancarios.tipoCuenta,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _FilaDato(
                  etiqueta: 'Número de cuenta',
                  valor: _DatosBancarios.numero,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _FilaDato(etiqueta: 'Titular', valor: _DatosBancarios.titular),
                _FilaDato(etiqueta: 'C.I.', valor: _DatosBancarios.ci),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Comprobante de la transferencia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Después de transferir, sube una foto o captura de pantalla del comprobante.',
            style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_imagenElegida != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _imagenBytes!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            InkWell(
              onTap: _elegirImagen,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 28,
                        color: AppColors.inkMuted,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Toca para elegir una imagen',
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_imagenElegida != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _subiendo ? null : _elegirImagen,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Elegir otra imagen'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _subiendo ? null : _subir,
            child: _subiendo
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Enviar comprobante'),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _subiendo
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Subir esto más tarde'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila "etiqueta: valor" dentro de la tarjeta de datos bancarios.
/// Usa SelectableText (no Text) para que la persona pueda mantener
/// presionado el número de cuenta y copiarlo directo a su app del banco.
class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  valor,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
