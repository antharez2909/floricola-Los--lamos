// ======================================================================
// LOGOTIPO DE LA APP: un monograma "LA" (Los Álamos)
// ======================================================================
// En vez de usar un ícono genérico de Material (como Icons.local_florist,
// que podría ser el logo de cualquier floristería), este widget dibuja
// un cuadrado con esquinas redondeadas y las iniciales "LA" en la
// tipografía serif de marca. Se ve una sola vez, grande, en la pantalla
// de login, pero está aquí como widget aparte por si se quisiera
// reutilizar en otro lado (una pantalla de "Acerca de", un splash, etc.)
// sin copiar y pegar el mismo código.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme.dart';

/// Uso: `const AppLogo()` para el tamaño por defecto (56),
/// o `const AppLogo(size: 40)` para uno más chico.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 56});

  /// Ancho y alto del cuadrado, en píxeles lógicos. El tamaño de la letra
  /// y el radio de las esquinas se calculan a partir de este mismo valor
  /// (size * 0.38 y size * 0.28), así el logo se ve proporcionado sin
  /// importar qué tan grande o chico se pida.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        'LA',
        style: GoogleFonts.fraunces(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          height: 1, // evita que Flutter agregue espacio extra arriba/abajo del texto
        ),
      ),
    );
  }
}
