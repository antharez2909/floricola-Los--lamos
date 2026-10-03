// ======================================================================
// PANTALLA PRINCIPAL: navegación por pestañas + Inicio, Clientes y Cuenta
// ======================================================================
// Este archivo agrupa todo lo que la persona ve DESPUÉS de iniciar sesión:
//   - HomeScreen: el "esqueleto" con la barra de pestañas de abajo.
//   - InicioTab: la pestaña de bienvenida (acerca de + contacto).
//   - ClientesTab: la lista de usuarios registrados (solo la ve el admin).
//   - CuentaTab: los datos de la persona que inició sesión + cerrar sesión.
// La pestaña de "Productos" vive en su propio archivo (productos_screen.dart)
// porque tiene bastante más lógica (agregar y eliminar).
//
// _Fila y _TarjetaLista, al principio del archivo, son piezas pequeñas de
// diseño que se repiten varias veces (una fila de "ícono + etiqueta + valor"
// dentro de una tarjeta blanca): en vez de repetir ese mismo bloque de
// widgets cuatro o cinco veces, se armó una sola vez aquí y se reutiliza.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_background.dart';
import '../api_service.dart';
import '../cart_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth_screens.dart';
import 'carrito_screen.dart';
import 'pedidos_screens.dart';
import 'productos_screen.dart';

/// Fila de ícono + texto dentro de una Card, con el ícono en su propio
/// círculo de color en vez del ícono plano por defecto de ListTile.
class _Fila extends StatelessWidget {
  const _Fila({required this.icono, required this.titulo, this.subtitulo})
    : destacado = null;

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, size: 17, color: AppColors.forestMid),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                  ),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitulo!, style: const TextStyle(fontSize: 14.5)),
                ],
              ],
            ),
          ),
          ?destacado,
        ],
      ),
    );
  }
}

/// Envuelve varias [_Fila] en una Card con separadores finos.
class _TarjetaLista extends StatelessWidget {
  const _TarjetaLista({required this.filas});

  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < filas.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            filas[i],
          ],
        ],
      ),
    );
  }
}

/// Empareja una pantalla (pagina) con su ícono y etiqueta en la barra de
/// abajo (destino), para poder armar ambas cosas juntas en una sola lista
/// y no tener que mantener dos listas separadas sincronizadas a mano.
class _Pestana {
  _Pestana(this.pagina, this.destino);

  final Widget pagina;
  final NavigationDestination destino;
}

/// Pantalla principal con barra de navegación inferior.
/// El administrador ve además la pestaña "Clientes".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Índice de la pestaña actualmente visible (0 = Inicio, 1 = Productos...).
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;

    // Se arma la lista de pestañas aquí, dentro de build(), en vez de una
    // sola vez al crear el widget, porque depende de 'u.esAdmin': si el
    // usuario cambiara (no pasa en esta app, pero es la forma correcta),
    // la lista de pestañas se recalcularía sola en el próximo build().
    final pestanas = <_Pestana>[
      _Pestana(
        InicioTab(
          usuario: u,
          onVerProductos: () => setState(() => _indice = 1),
        ),
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Inicio',
        ),
      ),
      _Pestana(
        ProductosScreen(esAdmin: u.esAdmin),
        const NavigationDestination(
          icon: Icon(Icons.local_florist_outlined),
          selectedIcon: Icon(Icons.local_florist),
          label: 'Productos',
        ),
      ),
      // El carrito solo tiene sentido para quien compra: un admin no
      // agrega productos a un carrito, así que esta pestaña no existe
      // para él (igual que "Clientes" no existe para un cliente).
      if (!u.esAdmin)
        _Pestana(
          const CarritoScreen(),
          NavigationDestination(
            // ValueListenableBuilder aquí, y no en HomeScreen, es lo que
            // permite que el numerito del carrito se actualice solo
            // (por ejemplo, mientras la persona sigue mirando la pestaña
            // de Productos) sin depender de que HomeScreen se reconstruya.
            icon: ValueListenableBuilder<List<ItemCarrito>>(
              valueListenable: CartService.instance.items,
              builder: (context, items, _) {
                final cantidad = items.fold(0, (s, i) => s + i.cantidad);
                final icono = const Icon(Icons.shopping_cart_outlined);
                return cantidad == 0
                    ? icono
                    : Badge(label: Text('$cantidad'), child: icono);
              },
            ),
            selectedIcon: const Icon(Icons.shopping_cart),
            label: 'Carrito',
          ),
        ),
      _Pestana(
        u.esAdmin ? const PedidosAdminScreen() : const PedidosScreen(),
        const NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Pedidos',
        ),
      ),
      // if (u.esAdmin) dentro de una lista literal de Dart: agrega este
      // elemento SOLO cuando la condición es verdadera. Así, un cliente
      // normal nunca llega a ver ni el botón ni la pantalla de Clientes
      // (no es solo un tema de "ocultar", el widget ni siquiera se crea).
      if (u.esAdmin)
        _Pestana(
          const ClientesTab(),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
        ),
      _Pestana(
        CuentaTab(usuario: u),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Mi cuenta',
        ),
      ),
    ];

    return Scaffold(
      // IndexedStack mantiene TODAS las pestañas construidas en memoria al
      // mismo tiempo, y solo muestra la que corresponde a "_indice". Esto es
      // a propósito: si se usara, por ejemplo, un simple "if" para mostrar
      // solo la pestaña activa, cada vez que la persona cambiara de pestaña
      // se perdería el scroll y habría que volver a pedir los datos al
      // servidor (por ejemplo, la lista de productos se recargaría cada vez).
      body: IndexedStack(
        index: _indice,
        children: [for (final p in pestanas) p.pagina],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        // Al tocar un ícono de la barra, solo se actualiza este número:
        // IndexedStack de arriba se encarga de mostrar la pestaña correcta.
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: [for (final p in pestanas) p.destino],
      ),
    );
  }
}

// ==================================================
// INICIO
// ==================================================

class InicioTab extends StatefulWidget {
  const InicioTab({
    super.key,
    required this.usuario,
    required this.onVerProductos,
  });

  final Usuario usuario;
  final VoidCallback onVerProductos;

  @override
  State<InicioTab> createState() => _InicioTabState();
}

class _InicioTabState extends State<InicioTab> {
  Map<String, dynamic>? _contenido;
  bool _cargandoContenido = true;
  bool _guardandoImagen = false;

  @override
  void initState() {
    super.initState();
    _cargarContenido();
  }

  Future<void> _cargarContenido() async {
    try {
      final contenido = await ApiService.instance.contenidoInicio();
      if (!mounted) return;
      final nombreFondo = contenido['fondo'] as String?;
      AppBackground.imageUrl.value = ApiService.instance.urlImagenInicio(
        nombreFondo,
      );
      setState(() => _contenido = contenido);
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _cargandoContenido = false);
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _elegirImagen({required bool comoFondo}) async {
    try {
      final imagen = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (imagen == null || !mounted) return;

      setState(() => _guardandoImagen = true);
      final bytes = await imagen.readAsBytes();
      if (comoFondo) {
        await ApiService.instance.subirFondoInicio(
          imagenBytes: bytes,
          nombreArchivo: imagen.name,
        );
      } else {
        await ApiService.instance.agregarImagenInicio(
          imagenBytes: bytes,
          nombreArchivo: imagen.name,
        );
      }
      await _cargarContenido();
      _aviso(comoFondo ? 'Fondo actualizado' : 'Imagen agregada al inicio');
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } catch (e) {
      debugPrint('No se pudo seleccionar o subir la imagen: $e');
      _aviso('No se pudo seleccionar o subir la imagen');
    } finally {
      if (mounted) setState(() => _guardandoImagen = false);
    }
  }

  Future<bool> _confirmarEliminacion(String mensaje) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Eliminar imagen?'),
            content: Text(mensaje),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _quitarFondo() async {
    if (!await _confirmarEliminacion('Se quitará el fondo personalizado.')) {
      return;
    }
    try {
      await ApiService.instance.quitarFondoInicio();
      await _cargarContenido();
      _aviso('Fondo eliminado');
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    }
  }

  Future<void> _quitarImagenGaleria(String nombre) async {
    if (!await _confirmarEliminacion('Se quitará esta imagen de la galería.')) {
      return;
    }
    try {
      await ApiService.instance.quitarImagenInicio(nombre);
      await _cargarContenido();
      _aviso('Imagen eliminada');
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final usuario = widget.usuario;
    final fondo = ApiService.instance.urlImagenInicio(
      _contenido?['fondo'] as String?,
    );
    final galeria = (_contenido?['galeria'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Florícola Los Álamos')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _heroInicio(
                fondo: fondo,
                nombre: usuario.nombres,
                esAdmin: usuario.esAdmin,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: widget.onVerProductos,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(
                  usuario.esAdmin ? 'Administrar productos' : 'Ver productos',
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Nuestra florícola', style: texto.titleMedium),
                  ),
                  if (usuario.esAdmin)
                    TextButton.icon(
                      onPressed: _guardandoImagen
                          ? null
                          : () => _elegirImagen(comoFondo: false),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Agregar fotos'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (galeria.isNotEmpty)
                SizedBox(
                  height: 178,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: galeria.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final nombre = galeria[index];
                      final url = ApiService.instance.urlImagenInicio(nombre);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          width: 250,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                url!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _imagenVacia(),
                              ),
                              if (usuario.esAdmin)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: _botonImagen(
                                    icono: Icons.delete_outline,
                                    etiqueta: 'Eliminar imagen',
                                    onPressed: () =>
                                        _quitarImagenGaleria(nombre),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else if (usuario.esAdmin)
                OutlinedButton.icon(
                  onPressed: _guardandoImagen
                      ? null
                      : () => _elegirImagen(comoFondo: false),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Agrega fotos para mostrar en el inicio'),
                )
              else
                _panelDecorativo(),
              const SizedBox(height: 24),
              Text('Acerca de', style: texto.titleMedium),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Somos una empresa dedicada a la venta de flores frescas '
                    'con retiro de pedidos directamente en la florícola. '
                    'Lo hacemos con calidad y compromiso.',
                    style: TextStyle(
                      color: AppColors.ink.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Contacto', style: texto.titleMedium),
              const SizedBox(height: 10),
              const _TarjetaLista(
                filas: [
                  _Fila(
                    icono: Icons.email_outlined,
                    titulo: 'Correo',
                    subtitulo: 'losalamos@gmail.com',
                  ),
                  _Fila(
                    icono: Icons.phone_outlined,
                    titulo: 'Teléfono',
                    subtitulo: '0980224624',
                  ),
                  _Fila(
                    icono: Icons.place_outlined,
                    titulo: 'Ubicación',
                    subtitulo: 'Quito, Ecuador',
                  ),
                ],
              ),
            ],
          ),
          if (_guardandoImagen || _cargandoContenido)
            const Positioned(
              top: 10,
              right: 20,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heroInicio({
    required String? fondo,
    required String nombre,
    required bool esAdmin,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 258,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fondo != null)
              Image.network(
                fondo,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fondoDegradado(),
              )
            else
              _fondoDegradado(),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.68),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FLORES CON HISTORIA',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Hola, $nombre',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    esAdmin
                        ? 'Tu espacio para dar vida a la florícola'
                        : 'Qué bueno verte de nuevo por la florícola',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (esAdmin)
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  children: [
                    _botonImagen(
                      icono: Icons.wallpaper_outlined,
                      etiqueta: 'Cambiar fondo',
                      onPressed: _guardandoImagen
                          ? null
                          : () => _elegirImagen(comoFondo: true),
                    ),
                    if (_contenido?['fondo'] != null) ...[
                      const SizedBox(width: 8),
                      _botonImagen(
                        icono: Icons.delete_outline,
                        etiqueta: 'Quitar fondo',
                        onPressed: _quitarFondo,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _botonImagen({
    required IconData icono,
    required String etiqueta,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: etiqueta,
      child: Material(
        color: Colors.black.withValues(alpha: 0.48),
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icono, color: Colors.white, size: 20),
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        ),
      ),
    );
  }

  Widget _fondoDegradado() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF527A62), Color(0xFF1B4332), Color(0xFF17382D)],
        ),
      ),
      child: const Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Icon(Icons.local_florist, color: Color(0x5578A88D), size: 116),
        ),
      ),
    );
  }

  Widget _imagenVacia() {
    return Container(
      color: AppColors.paper,
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_florist_outlined,
        color: AppColors.forestMid,
        size: 42,
      ),
    );
  }

  Widget _panelDecorativo() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: Icon(
          Icons.local_florist_outlined,
          color: AppColors.forestMid,
          size: 42,
        ),
      ),
    );
  }
}

// ==================================================
// CLIENTES (SOLO ADMIN)
// ==================================================

/// Pestaña visible solo para administradores: la lista de TODOS los
/// usuarios registrados (clientes y otros admins), pedida a GET /api/clientes.
/// Si un cliente normal llegara a ver esta clase (no debería, ver HomeScreen),
/// el propio backend igual rechazaría el pedido con 403 (ver requiere_admin
/// en api.py): la seguridad real está en el servidor, no en esconder el botón.
class ClientesTab extends StatefulWidget {
  const ClientesTab({super.key});

  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> {
  List<Usuario>?
  _clientes; // null = todavía no se cargó nada (ni éxito ni error)
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    // Se pide la lista apenas se crea esta pantalla, sin esperar ninguna
    // acción de la persona (por eso está en initState y no en un botón).
    _cargar();
  }

  /// Pide la lista de clientes al servidor. Se puede volver a llamar tanto
  /// al deslizar hacia abajo (RefreshIndicator) como al presionar
  /// "Reintentar" después de un error (ver ErrorConReintento en widgets.dart).
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultado = await ApiService.instance.clientes(porPagina: 50);
      if (mounted) setState(() => _clientes = resultado.datos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editarCliente(Usuario cliente) async {
    final usuarioActual = ApiService.instance.sesion.value;
    final cambios = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditorPerfilDialog(usuario: cliente),
    );
    if (cambios == null || cliente.id == null) return;

    try {
      final propio = usuarioActual?.id == cliente.id;
      final correoPendiente = propio
          ? await ApiService.instance.actualizarMiPerfil(cambios)
          : await ApiService.instance.actualizarCliente(cliente.id!, cambios);

      if (correoPendiente != null) {
        if (propio && mounted) {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => VerificarCorreoScreen(correo: correoPendiente),
            ),
          );
        } else {
          _aviso(
            'Datos guardados. Se envió un código de verificación a $correoPendiente.',
          );
        }
      } else {
        _aviso('Datos del usuario actualizados');
      }
      await _cargar();
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    // Patrón de "tres estados" que se repite igual en ProductosScreen:
    //   1. _clientes es null y _cargando es true  -> mostrar una rueda de carga
    //   2. _clientes sigue null pero ya no se está cargando -> hubo un error
    //   3. _clientes ya tiene datos (aunque sea una lista vacía) -> mostrarlos
    Widget cuerpo;
    if (_clientes == null && _cargando) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (_clientes == null) {
      cuerpo = ErrorConReintento(
        mensaje: _error ?? 'Error',
        onReintentar: _cargar,
      );
    } else {
      final lista = _clientes!;
      cuerpo = RefreshIndicator(
        onRefresh: _cargar,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lista.length,
          separatorBuilder: (context, i) =>
              const Divider(height: 1, indent: 72),
          itemBuilder: (context, i) {
            final c = lista[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: CircleAvatar(
                backgroundColor: AppColors.forest,
                foregroundColor: Colors.white,
                child: Text(c.inicial),
              ),
              title: Text(
                c.nombreCompleto,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                c.correo,
                style: const TextStyle(color: AppColors.inkMuted),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: Text(c.rol),
                    backgroundColor: c.esAdmin
                        ? AppColors.forest.withValues(alpha: 0.08)
                        : null,
                    labelStyle: TextStyle(
                      color: c.esAdmin ? AppColors.forest : AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide.none,
                  ),
                  IconButton(
                    tooltip: 'Editar usuario',
                    onPressed: c.id == null ? null : () => _editarCliente(c),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: cuerpo,
    );
  }
}

// ==================================================
// MI CUENTA
// ==================================================

/// Pestaña de "Mi cuenta": muestra los datos del usuario que inició sesión
/// (ya vienen en memoria desde el login, no hace falta pedirlos otra vez al
/// servidor) y el botón para cerrar sesión.
class CuentaTab extends StatelessWidget {
  const CuentaTab({super.key, required this.usuario});

  final Usuario usuario;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.forest,
                  foregroundColor: Colors.white,
                  child: Text(
                    usuario.inicial,
                    style: texto.headlineSmall?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                Text(usuario.nombreCompleto, style: texto.titleLarge),
                const SizedBox(height: 6),
                Chip(
                  label: Text(usuario.esAdmin ? 'Administrador' : 'Cliente'),
                  backgroundColor: usuario.esAdmin
                      ? AppColors.forest.withValues(alpha: 0.08)
                      : null,
                  labelStyle: TextStyle(
                    color: usuario.esAdmin
                        ? AppColors.forest
                        : AppColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _TarjetaLista(
            filas: [
              _Fila(
                icono: Icons.badge_outlined,
                titulo: 'Nombres',
                subtitulo: usuario.nombres,
              ),
              _Fila(
                icono: Icons.badge_outlined,
                titulo: 'Apellidos',
                subtitulo: usuario.apellidos,
              ),
              _Fila(
                icono: Icons.email_outlined,
                titulo: 'Correo',
                subtitulo: usuario.correo,
              ),
              _Fila(
                icono: Icons.cake_outlined,
                titulo: 'Edad',
                subtitulo: usuario.edad?.toString() ?? '—',
              ),
            ],
          ),
          if (usuario.correoPendiente != null) ...[
            const SizedBox(height: 14),
            Card(
              color: AppColors.clay.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Correo pendiente de verificación',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(usuario.correoPendiente!),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => VerificarCorreoScreen(
                              correo: usuario.correoPendiente!,
                            ),
                          ),
                        );
                      },
                      child: const Text('Ingresar código de verificación'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _editarMiPerfil(context, usuario),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar mis datos'),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => ApiService.instance.cerrarSesion(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

Future<void> _editarMiPerfil(BuildContext context, Usuario usuario) async {
  final cambios = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _EditorPerfilDialog(usuario: usuario),
  );
  if (cambios == null || !context.mounted) return;

  try {
    final correoPendiente = await ApiService.instance.actualizarMiPerfil(
      cambios,
    );
    if (!context.mounted) return;

    if (correoPendiente != null) {
      final verificado = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => VerificarCorreoScreen(correo: correoPendiente),
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verificado == true
                ? 'Perfil actualizado y correo verificado'
                : 'Datos guardados. Verifica el nuevo correo para activarlo.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
    }
  } on ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.mensaje)));
  }
}

class _EditorPerfilDialog extends StatefulWidget {
  const _EditorPerfilDialog({required this.usuario});

  final Usuario usuario;

  @override
  State<_EditorPerfilDialog> createState() => _EditorPerfilDialogState();
}

class _EditorPerfilDialogState extends State<_EditorPerfilDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _usuario = TextEditingController(text: widget.usuario.usuario);
  late final _nombres = TextEditingController(text: widget.usuario.nombres);
  late final _apellidos = TextEditingController(text: widget.usuario.apellidos);
  late final _correo = TextEditingController(text: widget.usuario.correo);
  late final _edad = TextEditingController(
    text: widget.usuario.edad?.toString() ?? '',
  );

  @override
  void dispose() {
    _usuario.dispose();
    _nombres.dispose();
    _apellidos.dispose();
    _correo.dispose();
    _edad.dispose();
    super.dispose();
  }

  String? _requerido(String? valor) =>
      valor == null || valor.trim().isEmpty ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar datos del usuario'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _usuario,
                  decoration: const InputDecoration(labelText: 'Usuario'),
                  validator: _requerido,
                ),
                TextFormField(
                  controller: _nombres,
                  decoration: const InputDecoration(labelText: 'Nombres'),
                  validator: _requerido,
                ),
                TextFormField(
                  controller: _apellidos,
                  decoration: const InputDecoration(labelText: 'Apellidos'),
                  validator: _requerido,
                ),
                TextFormField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    helperText: 'Si lo cambias, tendrás que verificarlo.',
                  ),
                  validator: (valor) {
                    final correo = valor?.trim() ?? '';
                    if (correo.isEmpty) return 'Campo obligatorio';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(correo)) {
                      return 'Correo no válido';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _edad,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Edad'),
                  validator: (valor) {
                    final edad = int.tryParse(valor ?? '');
                    if (edad == null || edad < 1 || edad > 120) {
                      return 'Ingresa una edad entre 1 y 120';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'usuario': _usuario.text.trim(),
              'nombres': _nombres.text.trim(),
              'apellidos': _apellidos.text.trim(),
              'correo': _correo.text.trim(),
              'edad': int.parse(_edad.text.trim()),
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
