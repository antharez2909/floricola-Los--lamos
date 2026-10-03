// ======================================================================
// WIDGETS COMPARTIDOS entre varias pantallas
// ======================================================================
// Cosas de UI que se repetirían igual en más de un lugar (por ahora,
// solo el estado de error con botón de reintentar) viven aquí para no
// duplicar código.

import 'package:flutter/material.dart';

import 'theme.dart';

/// Pantalla de error genérica: un ícono, el mensaje que llegó del
/// backend (o de la ApiException de red) y un botón para volver a
/// intentar la misma operación.
///
/// La usan ProductosScreen y ClientesTab cuando falla la carga inicial
/// de datos (por ejemplo, sin conexión al servidor Flask):
///     ErrorConReintento(mensaje: e.mensaje, onReintentar: _cargar)
class ErrorConReintento extends StatelessWidget {
  const ErrorConReintento({
    super.key,
    required this.mensaje,
    required this.onReintentar,
  });

  final String mensaje;
  final VoidCallback onReintentar; // función que se ejecuta al presionar "Reintentar"

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min, // ocupa solo el alto que necesita, no toda la pantalla
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.inkMuted),
            const SizedBox(height: 14),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
