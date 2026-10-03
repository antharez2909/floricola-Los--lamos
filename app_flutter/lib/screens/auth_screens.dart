// PANTALLAS DE SESIÓN: Login y Registro
// ======================================================================
// Dos pantallas relacionadas que viven en el mismo archivo porque
// comparten piezas pequeñas (la validación de correo, la caja de error).
// Ambas siguen el mismo patrón general de un formulario en Flutter:
//   1. Un GlobalKey<FormState> (_formKey) que identifica el formulario
//      y permite pedirle "valídate a ti mismo" antes de enviar nada.
//   2. Un TextEditingController por cada campo, que guarda lo que la
//      persona va escribiendo y se lee al momento de enviar.
//   3. Un 'validator' en cada TextFormField: una función que revisa el
//      texto y devuelve null si está bien, o un mensaje de error si no.
//   4. Una bandera _cargando que deshabilita el botón y muestra una
//      ruedita mientras se espera la respuesta del servidor, para evitar
//      que la persona presione "Ingresar" dos veces seguidas.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app_logo.dart';
import '../theme.dart';

// ----------------------------------------------------------------------
// Validaciones reutilizables entre Login y Registro
// ----------------------------------------------------------------------

/// Expresión regular simple para "algo@algo.algo": no valida que el
/// correo exista de verdad (para eso haría falta mandar un correo de
/// confirmación), solo que tenga la forma básica de un correo.
final _regexCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Validador genérico para campos que solo necesitan "no estar vacíos"
/// (Nombres, Apellidos). Se le pasa directo a la propiedad 'validator'
/// de un TextFormField.
String? _obligatorio(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

/// Validador del campo de correo: revisa primero que no esté vacío, y
/// luego que tenga forma de correo válido según _regexCorreo.
String? _validarCorreo(String? v) {
  if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
  if (!_regexCorreo.hasMatch(v.trim())) return 'Correo no válido';
  return null;
}

/// Caja con borde rojo y texto de error, usada tanto en Login como en
/// Registro para mostrar el mensaje que devuelve el servidor (por
/// ejemplo, "Credenciales incorrectas" o "Usuario ya registrado").
/// El nombre empieza con "_" porque es privada de este archivo.
class _CajaError extends StatelessWidget {
  const _CajaError(this.mensaje);
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC), // rojo muy claro, de fondo
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            // Expanded es necesario para que el texto pueda hacer salto
            // de línea si el mensaje es largo, en vez de desbordar la fila.
            child: Text(
              mensaje,
              style: const TextStyle(color: AppColors.danger, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// LOGIN
// ======================================================================

/// Pantalla de inicio de sesión. Es la primera pantalla que ve cualquier
/// persona sin sesión guardada (ver AuthGate en main.dart).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  bool _cargando = false; // true mientras se espera la respuesta de /api/login
  bool _verClave =
      false; // controla si la contraseña se muestra en texto plano o con puntos
  String? _error; // mensaje de error a mostrar (null = sin error)

  @override
  void dispose() {
    // Todo TextEditingController debe "liberarse" cuando el widget se
    // destruye, o Flutter deja una advertencia de fuga de memoria.
    _correo.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Se ejecuta al presionar "Ingresar" (o al dar Enter/Done en el
  /// teclado, ver onFieldSubmitted más abajo).
  Future<void> _entrar() async {
    // Si algún validator devuelve un mensaje de error, .validate()
    // los muestra automáticamente debajo de cada campo y devuelve
    // false: no tiene sentido llamar al servidor con datos inválidos.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null; // limpia cualquier error de un intento anterior
    });
    try {
      await ApiService.instance.iniciarSesion(
        _correo.text.trim(),
        _password.text,
      );
      // No hace falta navegar a ninguna pantalla aquí: iniciarSesion()
      // actualiza ApiService.instance.sesion, y AuthGate (en main.dart)
      // está escuchando ese valor: apenas cambia, AuthGate reconstruye
      // solo y muestra HomeScreen en vez de LoginScreen.
    } on ApiException catch (e) {
      // 'mounted' revisa que este widget siga "vivo" en pantalla antes
      // de llamar a setState. Como iniciarSesion() es async, existe la
      // posibilidad remota de que la persona haya salido de esta
      // pantalla mientras se esperaba la respuesta del servidor; sin
      // este chequeo, Flutter lanzaría una advertencia o un error.
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      // 'finally' se ejecuta tanto si _entrar() tuvo éxito como si
      // falló, así el botón siempre vuelve a habilitarse.
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Abre la pantalla de registro y espera a que se cierre.
  /// Navigator.push devuelve, cuando la pantalla se cierra, el valor que
  /// esa pantalla haya mandado con Navigator.pop(valor) (ver _registrar
  /// más abajo, que hace pop(true) si el registro salió bien).
  Future<void> _irARegistro() async {
    final creada = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const RegistroScreen()));
    if (creada == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Correo verificado. Ya puedes iniciar sesión.'),
        ),
      );
    }
  }

  Future<void> _irARecuperarPassword() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RecuperarPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // SafeArea evita que el contenido quede debajo de la barra de
        // estado o del notch/cámara del teléfono.
        child: Center(
          child: SingleChildScrollView(
            // Permite hacer scroll si el teclado en pantalla, al abrirse,
            // deja menos espacio vertical del que ocupa todo el formulario.
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              // En pantallas anchas (tablets), evita que el formulario se
              // estire de borde a borde: se limita a 420 de ancho y queda
              // centrado por el Center() de más arriba.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  // stretch: cada hijo (los campos, el botón) ocupa todo
                  // el ancho disponible de la columna.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo()),
                    const SizedBox(height: 16),
                    Text(
                      'Florícola Los Álamos',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Flores frescas para retirar en la florícola',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 36),

                    // Solo aparece si hubo un error en el último intento.
                    if (_error != null) _CajaError(_error!),

                    TextFormField(
                      controller: _correo,
                      keyboardType:
                          TextInputType.emailAddress, // teclado con "@" visible
                      autofillHints: const [AutofillHints.email], // sugiere autocompletar con el correo guardado del sistema
                      textInputAction: TextInputAction
                          .next, // el botón del teclado dice "Siguiente"
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: _validarCorreo,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: !_verClave, // oculta el texto con puntos, salvo que _verClave sea true
                      textInputAction: TextInputAction
                          .done, // el botón del teclado dice "Listo"
                      onFieldSubmitted: (_) => _cargando
                          ? null
                          : _entrar(), // Enter/Done = intentar entrar
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _verClave ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _verClave = !_verClave),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Ingresa tu contraseña'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      // Mientras _cargando es true, onPressed es 'null':
                      // así es como Flutter deshabilita un botón (se ve
                      // gris y no responde a toques).
                      onPressed: _cargando ? null : _entrar,
                      child: _cargando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Ingresar'),
                    ),
                    TextButton(
                      onPressed: _cargando ? null : _irARecuperarPassword,
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cargando ? null : _irARegistro,
                      child: const Text('¿No tienes cuenta? Regístrate'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// RECUPERACIÓN DE CONTRASEÑA
// ======================================================================

class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key});

  @override
  State<RecuperarPasswordScreen> createState() =>
      _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  final _password = TextEditingController();
  final _confirmar = TextEditingController();
  bool _codigoSolicitado = false;
  bool _completada = false;
  bool _cargando = false;
  String? _error;
  String? _mensaje;

  @override
  void dispose() {
    _correo.dispose();
    _codigo.dispose();
    _password.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _solicitarCodigo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
      _mensaje = null;
    });
    try {
      final mensaje = await ApiService.instance.solicitarRecuperacionPassword(
        _correo.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _codigoSolicitado = true;
        _mensaje = mensaje;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await ApiService.instance.restablecerPassword(
        correo: _correo.text.trim(),
        codigo: _codigo.text.trim(),
        nuevaPassword: _password.text,
      );
      if (mounted) setState(() => _completada = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String? _validarPassword(String? valor) {
    if (valor == null || valor.isEmpty) return 'Ingresa una contraseña';
    if (!RegExp(r'^(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,64}$')
        .hasMatch(valor)) {
      return 'Usa 8-64 caracteres, una mayúscula, un número y un signo';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) _CajaError(_error!),
                    if (_mensaje != null) ...[
                      Text(
                        _mensaje!,
                        style: const TextStyle(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _correo,
                      enabled: !_codigoSolicitado && !_completada,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: _validarCorreo,
                    ),
                    if (_codigoSolicitado && !_completada) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codigo,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Código de 6 dígitos',
                        ),
                        validator: (valor) =>
                            valor == null || !RegExp(r'^\d{6}$').hasMatch(valor)
                            ? 'Ingresa el código de 6 dígitos'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Nueva contraseña',
                        ),
                        validator: _validarPassword,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmar,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirma la nueva contraseña',
                        ),
                        validator: (valor) => valor != _password.text
                            ? 'Las contraseñas no coinciden'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_completada)
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Volver a iniciar sesión'),
                      )
                    else
                      FilledButton(
                        onPressed: _cargando
                            ? null
                            : _codigoSolicitado
                            ? _cambiarPassword
                            : _solicitarCodigo,
                        child: _cargando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _codigoSolicitado
                                    ? 'Cambiar contraseña'
                                    : 'Enviar código',
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// REGISTRO
// ======================================================================

/// Pantalla para crear una cuenta nueva. Se abre desde LoginScreen y, al
/// terminar con éxito, se cierra sola (Navigator.pop) devolviendo 'true'
/// para que LoginScreen muestre el aviso de "Cuenta creada".
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombres = TextEditingController();
  final _apellidos = TextEditingController();
  final _edad = TextEditingController();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  final _confirmar = TextEditingController(); // solo para comparar contra _password, no se envía al servidor
  bool _cargando = false;
  bool _verClave = false;
  String? _error;

  @override
  void dispose() {
    // Cada controller se libera al cerrar la pantalla, igual que en Login.
    _nombres.dispose();
    _apellidos.dispose();
    _edad.dispose();
    _correo.dispose();
    _password.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  /// Se ejecuta al presionar "Registrarse".
  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await ApiService.instance.registrar(
        nombres: _nombres.text.trim(),
        apellidos: _apellidos.text.trim(),
        correo: _correo.text.trim(),
        password: _password.text,
        // int.parse() es seguro aquí: el validator del campo 'Edad' ya
        // garantizó, antes de llegar a este punto, que el texto sí es
        // un número entre 1 y 120.
        edad: int.parse(_edad.text.trim()),
      );
      if (!mounted) return;
      final verificada = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => VerificarCorreoScreen(correo: _correo.text.trim()),
        ),
      );
      if (verificada == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) _CajaError(_error!),
                    TextFormField(
                      controller: _nombres,
                      textCapitalization: TextCapitalization
                          .words, // pone mayúscula al inicio de cada palabra
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Nombres'),
                      validator: _obligatorio,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apellidos,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Apellidos'),
                      validator: _obligatorio,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _edad,
                      keyboardType: TextInputType.number, // teclado numérico
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Edad'),
                      validator: (v) {
                        // int.tryParse (a diferencia de int.parse) devuelve
                        // null en vez de lanzar un error si el texto no es
                        // un número válido: perfecto para un validator,
                        // que debe devolver un mensaje, no tronar la app.
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 1 || n > 120) {
                          return 'Ingresa una edad válida';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _correo,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: _validarCorreo,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: !_verClave,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Contraseña (8 a 64 caracteres)',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _verClave ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _verClave = !_verClave),
                        ),
                      ),
                      validator: (v) {
                        final value = v ?? '';
                        if (value.length < 8) return 'Mínimo 8 caracteres';
                        if (value.length > 64) return 'Máximo 64 caracteres';
                        if (!RegExp(r'[A-Z]').hasMatch(value)) {
                          return 'Incluye al menos una mayúscula';
                        }
                        if (!RegExp(r'[0-9]').hasMatch(value)) {
                          return 'Incluye al menos un número';
                        }
                        if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
                          return 'Incluye al menos un signo especial';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmar,
                      obscureText: !_verClave,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Repite la contraseña',
                      ),
                      // Compara contra _password.text directamente (este
                      // campo nunca se manda al servidor, solo sirve para
                      // detectar errores de tipeo antes de enviar nada).
                      validator: (v) => v != _password.text
                          ? 'Las contraseñas no coinciden'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _cargando ? null : _registrar,
                      child: _cargando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Registrarse'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// VERIFICACIÓN DE CORREO
// ======================================================================

class VerificarCorreoScreen extends StatefulWidget {
  const VerificarCorreoScreen({super.key, required this.correo});
  final String correo;

  @override
  State<VerificarCorreoScreen> createState() => _VerificarCorreoScreenState();
}

class _VerificarCorreoScreenState extends State<VerificarCorreoScreen> {
  final _codigo = TextEditingController();
  bool _cargando = false;
  bool _reenviando = false;
  String? _error;
  String? _mensaje;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    if (_codigo.text.trim().length != 6) {
      setState(() => _error = 'Ingresa el código de 6 dígitos');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _mensaje = null;
    });
    try {
      await ApiService.instance.verificarCorreo(
        widget.correo,
        _codigo.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reenviar() async {
    setState(() {
      _reenviando = true;
      _error = null;
      _mensaje = null;
    });
    try {
      await ApiService.instance.reenviarCodigoVerificacion(widget.correo);
      if (mounted) {
        setState(() => _mensaje = 'Código reenviado. Revisa tu correo.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificar correo')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_read_outlined, size: 64),
                  const SizedBox(height: 20),
                  const Text(
                    'Revisa tu correo',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Enviamos un código de 6 dígitos a ${widget.correo}.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) _CajaError(_error!),
                  if (_mensaje != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_mensaje!, textAlign: TextAlign.center),
                    ),
                  TextField(
                    controller: _codigo,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, letterSpacing: 8),
                    decoration: const InputDecoration(
                      labelText: 'Código de verificación',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _cargando ? null : _verificar,
                    child: _cargando
                        ? const CircularProgressIndicator()
                        : const Text('Verificar correo'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _reenviando ? null : _reenviar,
                    child: _reenviando
                        ? const Text('Enviando...')
                        : const Text('Reenviar código'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
