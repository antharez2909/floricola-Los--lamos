// ======================================================================
// PANTALLA DE PRODUCTOS: catálogo, búsqueda, carrito y CRUD de admin
// ======================================================================

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:typed_data';

import '../api_service.dart';
import '../cart_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ProductosScreen extends StatefulWidget {
  const ProductosScreen({super.key, required this.esAdmin});

  final bool esAdmin;

  @override
  State<ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> {
  static const _porPagina = 10;

  final _buscador = TextEditingController();

  List<Producto>? _productos;
  int _total = 0;
  int _pagina = 1;
  String? _error;
  bool _cargando = true;
  bool _cargandoMas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _pagina = 1;
    });

    try {
      final resultado = await ApiService.instance.productos(
        pagina: 1,
        porPagina: _porPagina,
        buscar: _buscador.text.trim(),
      );

      if (mounted) {
        setState(() {
          _productos = resultado.datos;
          _total = resultado.total;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.mensaje;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  Future<void> _cargarMas() async {
    if (_productos == null || _productos!.length >= _total) {
      return;
    }

    setState(() {
      _cargandoMas = true;
    });

    try {
      final siguiente = _pagina + 1;

      final resultado = await ApiService.instance.productos(
        pagina: siguiente,
        porPagina: _porPagina,
        buscar: _buscador.text.trim(),
      );

      if (mounted) {
        setState(() {
          _productos = [..._productos!, ...resultado.datos];
          _pagina = siguiente;
        });
      }
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) {
        setState(() {
          _cargandoMas = false;
        });
      }
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _agregarAlCarrito(Producto producto) async {
    final cantidadActual = CartService.instance.items.value
        .where((item) => item.producto.id == producto.id)
        .fold<int>(0, (total, item) => total + item.cantidad);
    final disponible = producto.cantidad - cantidadActual;
    if (disponible <= 0) {
      _aviso('Ya tienes todas las unidades disponibles en el carrito');
      return;
    }

    final cantidad = await showDialog<int>(
      context: context,
      builder: (_) =>
          _DialogoCantidadProducto(producto: producto, disponible: disponible),
    );

    if (cantidad == null || !mounted) return;
    CartService.instance.agregar(producto, cantidad: cantidad);
    _aviso('Artículos agregados al carrito');
  }

  Future<void> _abrirFormulario({Producto? existente}) async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormularioProducto(existente: existente),
    );

    if (datos == null) return;

    try {
      if (existente == null) {
        await ApiService.instance.agregarProducto(
          nombre: datos['nombre'] as String,
          cantidad: datos['cantidad'] as int,
          precio: datos['precio'] as double,
          tamanoTalloCm: datos['tamano_tallo_cm'] as int,
          imagenBytes: datos['imagen_bytes'] as List<int>?,
          nombreArchivo: datos['imagen_nombre'] as String?,
        );

        _aviso('Producto agregado');
      } else {
        await ApiService.instance.actualizarProducto(
          id: existente.id,
          nombre: datos['nombre'] as String,
          cantidad: datos['cantidad'] as int,
          precio: datos['precio'] as double,
          tamanoTalloCm: datos['tamano_tallo_cm'] as int,
          imagenBytes: datos['imagen_bytes'] as List<int>?,
          nombreArchivo: datos['imagen_nombre'] as String?,
        );

        _aviso('Producto actualizado');
      }

      await _cargar();
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    }
  }

  Future<void> _eliminar(Producto p) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar "${p.nombre}" del inventario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await ApiService.instance.eliminarProducto(p.id);

      if (!mounted) return;

      setState(() {
        _productos = _productos?.where((x) => x.id != p.id).toList();

        if (_total > 0) {
          _total -= 1;
        }
      });

      _aviso('Producto eliminado');
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget cuerpo;

    if (_productos == null && _cargando) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (_productos == null) {
      cuerpo = ErrorConReintento(
        mensaje: _error ?? 'Error',
        onReintentar: _cargar,
      );
    } else {
      final lista = _productos!;
      final hayMas = lista.length < _total;

      cuerpo = RefreshIndicator(
        onRefresh: _cargar,
        child: lista.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.eco_outlined,
                          size: 40,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _buscador.text.isEmpty
                              ? 'Todavía no hay productos'
                              : 'Sin resultados para "${_buscador.text}"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: lista.length + (hayMas ? 1 : 0),
                separatorBuilder: (context, i) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == lista.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Center(
                        child: _cargandoMas
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: _cargarMas,
                                child: const Text('Cargar más'),
                              ),
                      ),
                    );
                  }

                  final p = lista[i];
                  final agotado = p.cantidad == 0;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _ImagenProducto(
                            url: ApiService.instance.urlImagenProducto(
                              p.imagenUrl,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  agotado
                                      ? 'Agotado · Tallo ${p.tamanoTalloCm} cm'
                                      : 'Stock: ${p.cantidad} · Tallo ${p.tamanoTalloCm} cm',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: agotado
                                        ? AppColors.danger
                                        : AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '\$${p.precio.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (widget.esAdmin) ...[
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: AppColors.inkMuted,
                              onPressed: () => _abrirFormulario(existente: p),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: AppColors.inkMuted,
                              onPressed: () => _eliminar(p),
                            ),
                          ] else
                            IconButton(
                              tooltip: 'Agregar al carrito',
                              icon: const Icon(
                                Icons.add_shopping_cart_outlined,
                                size: 20,
                              ),
                              color: agotado
                                  ? AppColors.inkMuted.withValues(alpha: 0.4)
                                  : AppColors.forestMid,
                              onPressed: agotado
                                  ? null
                                  : () => _agregarAlCarrito(p),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _buscador,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cargar(),
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _buscador.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _buscador.clear();
                          _cargar();
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: widget.esAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            )
          : null,
      body: cuerpo,
    );
  }
}

class _DialogoCantidadProducto extends StatefulWidget {
  const _DialogoCantidadProducto({
    required this.producto,
    required this.disponible,
  });

  final Producto producto;
  final int disponible;

  @override
  State<_DialogoCantidadProducto> createState() =>
      _DialogoCantidadProductoState();
}

class _DialogoCantidadProductoState extends State<_DialogoCantidadProducto> {
  final _formKey = GlobalKey<FormState>();
  late final _cantidad = TextEditingController(text: '1');

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  void _agregar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(int.parse(_cantidad.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Agregar ${widget.producto.nombre}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _cantidad,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Cantidad',
            helperText: 'Disponibles para agregar: ${widget.disponible}',
          ),
          validator: (valor) {
            final unidades = int.tryParse((valor ?? '').trim());
            if (unidades == null || unidades < 1) {
              return 'Ingresa una cantidad mayor que cero';
            }
            if (unidades > widget.disponible) {
              return 'Solo quedan ${widget.disponible} unidades disponibles';
            }
            return null;
          },
          onFieldSubmitted: (_) => _agregar(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _agregar, child: const Text('Agregar')),
      ],
    );
  }
}

// ==================================================
// FORMULARIO PARA CREAR O EDITAR UN PRODUCTO
// ==================================================

class _FormularioProducto extends StatefulWidget {
  const _FormularioProducto({this.existente});

  final Producto? existente;

  @override
  State<_FormularioProducto> createState() => _FormularioProductoState();
}

class _FormularioProductoState extends State<_FormularioProducto> {
  final _formKey = GlobalKey<FormState>();

  late final _nombre = TextEditingController(
    text: widget.existente?.nombre ?? '',
  );

  late final _cantidad = TextEditingController(
    text: widget.existente?.cantidad.toString() ?? '',
  );

  late final _precio = TextEditingController(
    text: widget.existente?.precio.toString() ?? '',
  );

  late final _talloCm = TextEditingController(
    text: widget.existente?.tamanoTalloCm.toString() ?? '',
  );

  XFile? _imagen;
  bool _seleccionandoImagen = false;

  bool get _editando => widget.existente != null;

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _precio.dispose();
    _talloCm.dispose();
    super.dispose();
  }

  double? _leerPrecio(String? v) {
    return double.tryParse((v ?? '').trim().replaceAll(',', '.'));
  }

  Future<void> _elegirImagen() async {
    setState(() {
      _seleccionandoImagen = true;
    });

    try {
      final imagen = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 82,
      );

      if (imagen != null && mounted) {
        setState(() {
          _imagen = imagen;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la galería')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _seleccionandoImagen = false;
        });
      }
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    List<int>? bytes;

    if (_imagen != null) {
      bytes = await _imagen!.readAsBytes();
    }

    if (!mounted) return;

    Navigator.of(context).pop(<String, dynamic>{
      'nombre': _nombre.text.trim(),
      'cantidad': int.parse(_cantidad.text.trim()),
      'precio': _leerPrecio(_precio.text)!,
      'tamano_tallo_cm': int.parse(_talloCm.text.trim()),
      'imagen_bytes': bytes,
      'imagen_nombre': _imagen?.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editando ? 'Editar producto' : 'Nuevo producto'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _seleccionandoImagen ? null : _elegirImagen,
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.inkMuted.withValues(alpha: 0.25),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _imagen == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 38,
                              color: AppColors.forestMid,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _editando
                                  ? 'Toca para cambiar la foto'
                                  : 'Toca para seleccionar una foto',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : FutureBuilder<List<int>>(
                          future: _imagen!.readAsBytes(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            return Image.memory(
                              Uint8List.fromList(snapshot.data!),
                              fit: BoxFit.cover,
                              width: double.infinity,
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombre,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) {
                    return 'Ingresa el nombre';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cantidad,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Cantidad'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());

                  return (n == null || n < 0) ? 'Cantidad no válida' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precio,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Precio (\$)'),
                validator: (v) {
                  final n = _leerPrecio(v);

                  return (n == null || n < 0) ? 'Precio no válido' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _talloCm,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Tamaño del tallo (cm)',
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());

                  return (n == null || n < 1 || n > 200)
                      ? 'Ingresa un valor entre 1 y 200'
                      : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardar,
          child: Text(_editando ? 'Guardar cambios' : 'Guardar'),
        ),
      ],
    );
  }
}

class _ImagenProducto extends StatelessWidget {
  const _ImagenProducto({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(Icons.eco_outlined, size: 25, color: AppColors.forestMid)
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: AppColors.inkMuted,
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
    );
  }
}
