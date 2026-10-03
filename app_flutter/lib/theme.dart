// ======================================================================
// TEMA VISUAL DE LA APLICACIÓN (AppTheme)
// ======================================================================
// Centraliza y estandariza la paleta de colores, tipografías y componentes
// visuales de la aplicación. Evita duplicar código de diseño en las pantallas.

import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';

/// ======================================================================
/// PALETA DE COLORES (AppColors)
/// Agrupa los valores hex de color utilizados en la interfaz.
/// ======================================================================
class AppColors {
  // Constructor privado para evitar que la clase sea instanciada accidentalmente
  AppColors._();

  // Verdes corporativos e identitarios
  static const forest = Color(
    0xFF1B4332,
  ); // Verde muy oscuro (para elementos destacados y SnackBars)
  static const forestMid = Color(
    0xFF2D6A4F,
  ); // Verde principal (usado en botones primarios y focos)
  static const sage = Color(
    0xFF74A57F,
  ); // Verde suave / secundario (usado en acentos y chips)

  // Fondos y delimitadores
  static const paper = Color(
    0xFFF0F4B8,
  ); // Fondo general verde lima suave
  static const card = Color(
    0xFFFFFFFF,
  ); // Fondo para contenedores, tarjetas y campos de texto
  static const hairline = Color(
    0xFFDCE3D8,
  ); // Color fino para bordes y divisores discretos

  // Colores de tipografía / texto
  static const ink = Color(
    0xFF20281F,
  ); // Texto principal (reemplaza al negro puro para suavizar la lectura)
  static const inkMuted = Color(
    0xFF5B675A,
  ); // Texto secundario, subtítulos o etiquetas deshabilitadas

  // Estados y acentos suplementarios
  static const clay = Color(0xFFB2745A); // Color de acento cálido
  static const danger = Color(
    0xFFB3261E,
  ); // Rojo estandarizado para avisos de error y validaciones
}

/// ======================================================================
/// CONFIGURACIÓN GENERAL DEL TEMA (AppTheme)
/// Retorna un objeto [ThemeData] configurado para aplicarse en MaterialApp.
/// ======================================================================
class AppTheme {
  AppTheme._();

  /// Genera la configuración del tema claro (Light Mode) para la app.
  static ThemeData light() {
    // -------------------------------------------------------------------
    // 1) ESQUEMA DE COLOR BASE Y FONDO DE LA PANTALLA
    // -------------------------------------------------------------------
    final base = ThemeData(
      useMaterial3: true, // Habilita los componentes y especificaciones de Material Design 3
      colorScheme: const ColorScheme.light(
        primary: AppColors.forestMid,
        onPrimary: Colors.white,
        secondary: AppColors.sage,
        surface: AppColors.card,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    // -------------------------------------------------------------------
    // 2) ESTILOS DE FUENTE Y TIPOGRAFÍA
    // -------------------------------------------------------------------
    // Usamos TextStyle nativo para evitar la colisión con material_ui
    final material.TextTheme sansTextTheme = base.textTheme.apply(
      fontFamily: 'PublicSans',
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    const serifStyle = TextStyle(
      fontFamily: 'Fraunces',
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
    );

    // -------------------------------------------------------------------
    // 3) CONSTRUCCIÓN Y PERSONALIZACIÓN DE WIDGETS
    // -------------------------------------------------------------------
    return base.copyWith(
      // Aplica el tema de texto personalizado
      textTheme: sansTextTheme,

      // Barra superior de la aplicación (AppBar)
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        surfaceTintColor:
            Colors.transparent, // Quita la sombra/tinción al hacer scroll
        elevation: 0,
        centerTitle: false,
        titleTextStyle: serifStyle.copyWith(
          fontSize: 20,
        ), // Título con tipografía Fraunces
      ),

      // Estilo de tarjetas (Card)
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0, // Tarjetas planas con bordes delineados
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.hairline), // Borde sutil
        ),
      ),

      // Líneas divisorias
      dividerTheme: const DividerThemeData(color: AppColors.hairline, space: 1),

      // Cajas de entrada de texto (TextField / TextFormField)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        // Estado normal
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        // Estado habilitado pero sin foco
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        // Estado activo / enfocado por el usuario
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.forestMid, width: 1.4),
        ),
        // Estado cuando hay un error de validación
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),

      // Botón principal (FilledButton)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forestMid,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999), // Forma redonda / píldora
          ),
          textStyle: sansTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),

      // Botón secundario con borde (OutlinedButton)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),

      // Botón plano solo de texto (TextButton)
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.forestMid),
      ),

      // Botón flotante de acción (FAB)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.forest,
        foregroundColor: Colors.white,
      ),

      // Etiquetas / Chips decorativos e informativos
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.paper,
        side: const BorderSide(color: AppColors.hairline),
        labelStyle: const TextStyle(color: AppColors.ink, fontSize: 12),
      ),

      // Barra de navegación inferior (BottomNavigationBar / NavigationBar)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 68,
        // Cambia el estilo del texto dinámicamente según si la pestaña está seleccionada
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.forestMid : AppColors.inkMuted,
          );
        }),
        // Cambia el color del ícono según si la pestaña está seleccionada
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.forestMid : AppColors.inkMuted,
            size: 24,
          );
        }),
      ),

      // Ventanas emergentes y diálogos de alerta (Dialog)
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // Mensajes flotantes de notificación (SnackBar)
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.forest,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior
            .floating, // Flota sobre la pantalla en lugar de pegarse abajo
      ),
    );
  }
}
