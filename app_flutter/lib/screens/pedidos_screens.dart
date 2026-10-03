// ======================================================================
// PANTALLAS DE PEDIDOS: "Mis pedidos" (cliente) y "Pedidos" (admin)
// ======================================================================
// Las dos pantallas de lista (PedidosScreen y PedidosAdminScreen)
// comparten casi todo: piden GET /api/pedidos paginado y muestran cada
// fila con fecha, estado y total. La diferencia es que el backend, para
// un cliente, ya filtra solo SUS pedidos automáticamente (ver
// listar_pedidos en api.py); para el admin, trae todos y permite además
// elegir un estado con el que filtrar.
//
// Al tocar cualquier pedido de la lista, ambas abren la misma pantalla
// de detalle (DetallePedidoScreen), que pide GET /api/pedidos/<id> para
// traer las líneas y la factura completas. El admin, además, puede
// cambiar el estado del pedido desde esa misma pantalla.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'comprobante_screen.dart';

/// Colores discretos por estado, solo para que la lista se lea rápido
/// de un vistazo (no representan nada más que eso).
String _etiquetaEstadoPedido(String estado) {
  switch (estado) {
    case 'listo_para_retiro':
      return 'Listo para retiro';
    case 'retirado':
      return 'Retirado';
    case 'cancelado':
      return 'Cancelado';
    default:
      return 'Pendiente';
  }
}

Color _colorEstado(String estado) {
  switch (estado) {
    case 'retirado':
      return AppColors.forestMid;
    case 'cancelado':
      return AppColors.danger;
    case 'listo_para_retiro':
      return AppColors.sage;
    default: // pendiente
      return AppColors.clay;
  }
}

/// Igual que _colorEstado, pero para el estado del PAGO (una cosa
/// separada del estado del pedido; ver el comentario al inicio de
/// pagos_transferencia.sql sobre por qué son dos columnas distintas).
Color _colorEstadoPago(String estadoPago) {
  switch (estadoPago) {
    case 'confirmado':
      return AppColors.forestMid;
    case 'rechazado':
      return AppColors.danger;
    case 'en_revision':
      return AppColors.clay;
    default: // pendiente
      return AppColors.inkMuted;
  }
}

String _etiquetaEstadoPago(String estadoPago) {
  switch (estadoPago) {
    case 'confirmado':
      return 'Pago confirmado';
    case 'rechazado':
      return 'Pago rechazado';
    case 'en_revision':
      return 'Comprobante en revisión';
    default:
      return 'Pago pendiente';
  }
}

String _formatoFecha(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

// ======================================================================
// LISTA: "Mis pedidos" (cliente)
// ======================================================================

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  List<Map<String, dynamic>>? _pedidos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // por_pagina alto: el historial personal de pedidos de un cliente
      // rara vez pasa de unas pocas decenas, así que aquí se trae de una
      // sola vez en vez de armar "cargar más" (a diferencia del catálogo
      // de productos, que sí necesita paginar de verdad).
      final resultado = await ApiService.instance.pedidos(porPagina: 50);
      if (mounted) setState(() => _pedidos = resultado.datos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos')),
      body: _ListaPedidos(
        pedidos: _pedidos,
        cargando: _cargando,
        error: _error,
        onReintentar: _cargar,
        onRefrescar: _cargar,
        esAdmin: false,
      ),
    );
  }
}

// ======================================================================
// LISTA: "Pedidos" (admin, con filtro por estado)
// ======================================================================

class PedidosAdminScreen extends StatefulWidget {
  const PedidosAdminScreen({super.key});

  @override
  State<PedidosAdminScreen> createState() => _PedidosAdminScreenState();
}

class _PedidosAdminScreenState extends State<PedidosAdminScreen> {
  static const _estados = [
    'todos',
    'pendiente',
    'listo_para_retiro',
    'retirado',
    'cancelado',
  ];

  List<Map<String, dynamic>>? _pedidos;
  String? _error;
  bool _cargando = true;
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultado = await ApiService.instance.pedidos(
        porPagina: 50,
        estado: _filtro == 'todos' ? null : _filtro,
      );
      if (mounted) setState(() => _pedidos = resultado.datos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _estados.length,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final estado = _estados[i];
                  final activo = estado == _filtro;
                  return ChoiceChip(
                    label: Text(estado[0].toUpperCase() + estado.substring(1)),
                    selected: activo,
                    onSelected: (_) {
                      setState(() => _filtro = estado);
                      _cargar();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
      body: _ListaPedidos(
        pedidos: _pedidos,
        cargando: _cargando,
        error: _error,
        onReintentar: _cargar,
        onRefrescar: _cargar,
        esAdmin: true,
      ),
    );
  }
}

/// Lista compartida entre PedidosScreen y PedidosAdminScreen: recibe los
/// datos ya cargados y solo se encarga de dibujarlos y de navegar al
/// detalle. Al volver del detalle se refresca (por si el admin cambió el
/// estado), pidiendo de nuevo la lista completa con 'onRefrescar'.
class _ListaPedidos extends StatelessWidget {
  const _ListaPedidos({
    required this.pedidos,
    required this.cargando,
    required this.error,
    required this.onReintentar,
    required this.onRefrescar,
    required this.esAdmin,
  });

  final List<Map<String, dynamic>>? pedidos;
  final bool cargando;
  final String? error;
  final Future<void> Function() onReintentar;
  final Future<void> Function() onRefrescar;
  final bool esAdmin;

  Future<void> _eliminarPedido(BuildContext context, int pedidoId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar pedido cancelado'),
        content: Text('¿Deseas eliminar permanentemente el pedido #$pedidoId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    try {
      await ApiService.instance.eliminarPedido(pedidoId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Pedido #$pedidoId eliminado')));
      await onRefrescar();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (pedidos == null && cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pedidos == null) {
      return ErrorConReintento(
        mensaje: error ?? 'Error',
        onReintentar: onReintentar,
      );
    }
    if (pedidos!.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefrescar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Padding(
              padding: EdgeInsets.fromLTRB(32, 96, 32, 32),
              child: Center(child: Text('No hay pedidos por aquí todavía.')),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: pedidos!.length,
        separatorBuilder: (context, i) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = pedidos![i];
          final estado = p['estado'] as String;
          final pedidoId = p['id'] as int;
          final puedeEliminar = esAdmin && estado == 'cancelado';
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              title: Text(
                esAdmin
                    ? 'Pedido #${p['id']} · ${p['cliente']}'
                    : 'Pedido #${p['id']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _formatoFecha(DateTime.parse(p['fecha'] as String)),
              ),
              trailing: SizedBox(
                width: puedeEliminar ? 154 : 90,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${(p['total'] as num).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Chip(
                          label: Text(
                            estado,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: _colorEstado(estado)
                              .withValues(alpha: 0.1),
                          labelStyle: TextStyle(
                            color: _colorEstado(estado),
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    if (puedeEliminar)
                      IconButton(
                        tooltip: 'Eliminar pedido cancelado',
                        onPressed: () => _eliminarPedido(context, pedidoId),
                        color: AppColors.danger,
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DetallePedidoScreen(
                      pedidoId: p['id'] as int,
                      esAdmin: esAdmin,
                    ),
                  ),
                );
                onRefrescar(); // por si el admin cambió el estado en el detalle
              },
            ),
          );
        },
      ),
    );
  }
}

// ======================================================================
// DETALLE DE UN PEDIDO (compartido entre cliente y admin)
// ======================================================================

class DetallePedidoScreen extends StatefulWidget {
  const DetallePedidoScreen({
    super.key,
    required this.pedidoId,
    required this.esAdmin,
  });

  final int pedidoId;
  final bool esAdmin;

  @override
  State<DetallePedidoScreen> createState() => _DetallePedidoScreenState();
}

class _DetallePedidoScreenState extends State<DetallePedidoScreen> {
  static const _estados = [
    'pendiente',
    'listo_para_retiro',
    'retirado',
    'cancelado',
  ];

  Pedido? _pedido;
  String? _error;
  bool _cargando = true;
  bool _actualizandoEstado = false;
  bool _eliminandoPedido = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pedido = await ApiService.instance.detallePedido(widget.pedidoId);
      if (mounted) setState(() => _pedido = pedido);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Solo el admin ve el selector que llama a esto (ver el 'if
  /// (widget.esAdmin)' en build). Cambia el estado en el servidor y
  /// vuelve a cargar el pedido para reflejar el cambio en pantalla.
  Future<void> _cambiarEstado(String nuevoEstado) async {
    setState(() => _actualizandoEstado = true);
    try {
      await ApiService.instance.actualizarEstadoPedido(
        widget.pedidoId,
        nuevoEstado,
      );
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _actualizandoEstado = false);
    }
  }

  Future<void> _eliminarPedido() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar pedido cancelado'),
        content: const Text(
          'Esta acción eliminará permanentemente el pedido y sus datos '
          'asociados. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Conservar pedido'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _eliminandoPedido = true);
    try {
      await ApiService.instance.eliminarPedido(widget.pedidoId);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _eliminandoPedido = false);
    }
  }

  /// Cliente: abre la pantalla de datos bancarios y permite subir el comprobante.
  /// Al volver (haya subido algo o no), se recarga el pedido por si el
  /// estado de pago cambió a 'en_revision'.
  Future<void> _irASubirComprobante() async {
    final pedido = _pedido;
    if (pedido == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ComprobanteScreen(pedidoId: widget.pedidoId, total: pedido.total),
      ),
    );
    _cargar();
  }

  /// Muestra la imagen del comprobante en un diálogo a pantalla casi
  /// completa, tanto para que el cliente confirme qué envió como para
  /// que el admin la revise antes de decidir.
  Future<void> _verComprobante() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: FutureBuilder<Uint8List>(
          future: ApiService.instance.comprobante(widget.pedidoId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).mensaje
                        : 'No se pudo cargar el comprobante',
                  ),
                ),
              );
            }
            return InteractiveViewer(
              // Permite hacer zoom con los dedos: útil para leer bien el
              // número de referencia o la hora de una transferencia.
              child: Image.memory(snapshot.data!, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }

  /// Solo admin: confirma o rechaza el pago después de ver el comprobante.
  Future<void> _revisarPago({required bool confirmar}) async {
    setState(() => _actualizandoEstado = true);
    try {
      await ApiService.instance.revisarPago(
        widget.pedidoId,
        confirmar: confirmar,
      );
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _actualizandoEstado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget cuerpo;
    if (_pedido == null && _cargando) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (_pedido == null) {
      cuerpo = ErrorConReintento(
        mensaje: _error ?? 'Error',
        onReintentar: _cargar,
      );
    } else {
      final pedido = _pedido!;
      cuerpo = ListView(
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
                      Text(
                        'Pedido #${pedido.id}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Chip(
                        label: Text(_etiquetaEstadoPedido(pedido.estado)),
                        backgroundColor: _colorEstado(pedido.estado)
                            .withValues(alpha: 0.1),
                        labelStyle: TextStyle(
                          color: _colorEstado(pedido.estado),
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatoFecha(pedido.fecha),
                    style: const TextStyle(color: AppColors.inkMuted),
                  ),
                  if (pedido.numeroFactura != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Factura: ${pedido.numeroFactura}',
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ],

                  // Solo el admin puede avanzar el estado del pedido.
                  if (widget.esAdmin) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Text(
                      'Cambiar estado',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _estados.map((estado) {
                        final activo = estado == pedido.estado;
                        return ChoiceChip(
                          label: Text(_etiquetaEstadoPedido(estado)),
                          selected: activo,
                          onSelected: _actualizandoEstado || activo
                              ? null
                              : (_) => _cambiarEstado(estado),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.esAdmin && pedido.estado == 'cancelado') ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _eliminandoPedido ? null : _eliminarPedido,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              icon: _eliminandoPedido
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(
                _eliminandoPedido ? 'Eliminando…' : 'Eliminar pedido cancelado',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Pago', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        pedido.estadoPago == 'confirmado'
                            ? Icons.check_circle_outline
                            : pedido.estadoPago == 'rechazado'
                            ? Icons.error_outline
                            : Icons.hourglass_empty,
                        size: 18,
                        color: _colorEstadoPago(pedido.estadoPago),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _etiquetaEstadoPago(pedido.estadoPago),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _colorEstadoPago(pedido.estadoPago),
                        ),
                      ),
                    ],
                  ),

                  // ---- Vista del CLIENTE ----
                  if (!widget.esAdmin) ...[
                    if (pedido.estadoPago == 'pendiente' ||
                        pedido.estadoPago == 'rechazado') ...[
                      const SizedBox(height: 12),
                      if (pedido.estadoPago == 'rechazado')
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'El comprobante anterior no pudo confirmarse. Sube uno nuevo.',
                            style: TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _irASubirComprobante,
                        icon: const Icon(Icons.upload_outlined, size: 18),
                        label: Text(
                          pedido.estadoPago == 'rechazado'
                              ? 'Subir otro comprobante'
                              : 'Pagar por transferencia',
                        ),
                      ),
                    ] else if (pedido.tieneComprobante) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _verComprobante,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text('Ver mi comprobante'),
                      ),
                    ],
                  ],

                  // ---- Vista del ADMIN ----
                  if (widget.esAdmin && pedido.tieneComprobante) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _verComprobante,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Ver comprobante'),
                    ),
                    if (pedido.estadoPago == 'en_revision') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _actualizandoEstado
                                  ? null
                                  : () => _revisarPago(confirmar: false),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Rechazar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _actualizandoEstado
                                  ? null
                                  : () => _revisarPago(confirmar: true),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF218838),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Confirmar pago'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  if (widget.esAdmin && !pedido.tieneComprobante) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'El cliente todavía no sube ningún comprobante.',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text('Productos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < pedido.items.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pedido.items[i].nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${pedido.items[i].cantidad} x \$${pedido.items[i].precioUnitario.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '\$${pedido.items[i].subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '\$${pedido.total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del pedido')),
      body: cuerpo,
    );
  }
}
