# ======================================================================
# API JSON PARA LA APP MÓVIL (FLUTTER)
# ======================================================================
# Este archivo es un "Blueprint" de Flask: un grupo de rutas que se
# registra dentro de app.py (con app.register_blueprint(api_bp)).
#
# La diferencia con las rutas de app.py es el formato de respuesta:
#   - app.py     -> devuelve páginas HTML (render_template), para el navegador.
#   - api.py     -> devuelve JSON (jsonify), para que la app Flutter lo lea.
#
# Cómo sabe el servidor quién hace cada pedido (sesión sin cookies):
#   1. El cliente manda su correo y contraseña a POST /api/login.
#   2. Si son correctos, el servidor genera un "token": un texto firmado
#      digitalmente que dice "este correo inició sesión" y una fecha de
#      expiración. Se firma con la SECRET_KEY de la app, así que nadie
#      puede inventarse un token válido sin conocer esa clave.
#   3. La app Flutter guarda ese token en el teléfono y lo manda en cada
#      pedido siguiente, dentro de la cabecera HTTP:
#          Authorization: Bearer <token>
#   4. Las rutas protegidas (decoradas con @requiere_token) leen esa
#      cabecera, verifican la firma y, si es válida, ya saben qué usuario
#      está haciendo el pedido sin tener que preguntar contraseña otra vez.
#
# Este mecanismo (JWT-like, aquí implementado con itsdangerous) es el
# equivalente, para una API, a lo que "session" hace en la web con cookies.

import math
import hashlib
import hmac
import json
import os
import tempfile
import uuid
import re
import secrets
import time
from datetime import datetime, timedelta
from email.message import EmailMessage
import smtplib
from functools import wraps

from flask import Blueprint, current_app, g, jsonify, request, send_from_directory
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from werkzeug.exceptions import HTTPException
from werkzeug.utils import secure_filename

from database import get_connection
from seguridad import hash_password, verificar_password

# Blueprint: todas las rutas que se definan con @api_bp más abajo
# terminan bajo la ruta /api/... (por url_prefix="/api").
# Ejemplo: @api_bp.post("/login") se sirve en POST /api/login
api_bp = Blueprint("api", __name__, url_prefix="/api")

# Cuánto tiempo dura un token antes de que la app tenga que pedir
# el correo y la contraseña de nuevo. 7 días * 24 horas * 3600 segundos.
TOKEN_DURACION = 7 * 24 * 3600  # 7 días


@api_bp.get("/status")
def estado_servicio():
    return jsonify({"status": "ok"})


# Imágenes públicas de los productos del catálogo. No contienen datos
# personales ni comprobantes de pago, por eso pueden ser servidas al
# catálogo sin exigir el token de autenticación.
EXTENSIONES_IMAGEN_PRODUCTO = {"jpg", "jpeg", "png", "webp"}
MAX_IMAGENES_INICIO = 12


def _carpeta_imagenes_productos():
    carpeta = os.path.join(current_app.config["UPLOAD_FOLDER_BASE"], "productos")
    os.makedirs(carpeta, exist_ok=True)
    return carpeta


def _guardar_imagen_producto(archivo, producto_id):
    """Guarda una imagen con un nombre generado por el servidor."""
    if archivo is None or not archivo.filename:
        return None

    original = secure_filename(archivo.filename)
    extension = original.rsplit(".", 1)[-1].lower() if "." in original else ""
    if extension not in EXTENSIONES_IMAGEN_PRODUCTO:
        raise ValueError("La imagen debe ser JPG, JPEG, PNG o WEBP")

    nombre = f"producto_{producto_id}_{uuid.uuid4().hex}.{extension}"
    ruta = os.path.join(_carpeta_imagenes_productos(), nombre)
    archivo.save(ruta)
    try:
        if os.path.getsize(ruta) > 5 * 1024 * 1024:
            os.remove(ruta)
            raise ValueError("La imagen no puede superar 5 MB")
    except OSError:
        if os.path.isfile(ruta):
            os.remove(ruta)
        raise ValueError("No se pudo guardar la imagen")
    return nombre


def _borrar_imagen_producto(nombre):
    if not nombre:
        return
    ruta = os.path.join(_carpeta_imagenes_productos(), os.path.basename(nombre))
    try:
        if os.path.isfile(ruta):
            os.remove(ruta)
    except OSError:
        pass


def _carpeta_inicio():
    carpeta = os.path.join(current_app.config["UPLOAD_FOLDER_BASE"], "inicio")
    os.makedirs(carpeta, exist_ok=True)
    return carpeta


def _archivo_configuracion_inicio():
    return os.path.join(_carpeta_inicio(), "contenido.json")


def _contenido_inicio():
    ruta = _archivo_configuracion_inicio()
    if not os.path.exists(ruta):
        return {"fondo": None, "galeria": []}

    with open(ruta, encoding="utf-8") as archivo:
        contenido = json.load(archivo)

    fondo = contenido.get("fondo")
    galeria = contenido.get("galeria", [])
    if (fondo is not None and not isinstance(fondo, str)) or not isinstance(galeria, list):
        raise ValueError("La configuración guardada del inicio no es válida")
    return {"fondo": fondo, "galeria": galeria}


def _guardar_contenido_inicio(contenido):
    carpeta = _carpeta_inicio()
    descriptor, temporal = tempfile.mkstemp(
        prefix=".contenido_inicio_",
        suffix=".tmp",
        dir=carpeta,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as archivo:
            json.dump(contenido, archivo, ensure_ascii=False)
            archivo.flush()
            os.fsync(archivo.fileno())
        os.replace(temporal, _archivo_configuracion_inicio())
    except Exception:
        if os.path.exists(temporal):
            os.remove(temporal)
        raise


def _guardar_imagen_inicio(archivo, categoria):
    if archivo is None or not archivo.filename:
        raise ValueError("Selecciona una imagen")

    original = secure_filename(archivo.filename)
    extension = original.rsplit(".", 1)[-1].lower() if "." in original else ""
    if extension not in EXTENSIONES_IMAGEN_PRODUCTO:
        raise ValueError("La imagen debe ser JPG, JPEG, PNG o WEBP")

    nombre = f"{categoria}_{uuid.uuid4().hex}.{extension}"
    ruta = os.path.join(_carpeta_inicio(), nombre)
    archivo.save(ruta)
    try:
        if os.path.getsize(ruta) > 5 * 1024 * 1024:
            os.remove(ruta)
            raise ValueError("La imagen no puede superar 5 MB")
    except OSError:
        if os.path.isfile(ruta):
            os.remove(ruta)
        raise ValueError("No se pudo guardar la imagen")
    return nombre


def _borrar_imagen_inicio(nombre):
    if not nombre:
        return
    ruta = os.path.join(_carpeta_inicio(), os.path.basename(nombre))
    if os.path.isfile(ruta):
        os.remove(ruta)


# ======================================================================
# UTILIDADES INTERNAS
# ======================================================================
# Funciones que empiezan con "_" son privadas de este archivo: ayudan a
# las rutas de abajo pero no son rutas en sí mismas.

def _error(mensaje, codigo=400):
    """
    Da forma estándar a cualquier respuesta de error:
        { "error": "texto explicando qué salió mal" }
    junto con el código HTTP correspondiente (400 = pedido inválido,
    401 = no autenticado, 403 = sin permiso, 404 = no existe, etc.)
    Así la app Flutter siempre sabe dónde buscar el mensaje de error.
    """
    return jsonify({"error": mensaje}), codigo


def _consulta(sql, params=(), uno=False):
    """
    Ejecuta un SELECT y devuelve los resultados como diccionarios
    (por eso cursor(dictionary=True): en vez de tuplas ("Ana", 30),
    da {"nombre": "Ana", "edad": 30}, más fácil de convertir a JSON).

    - sql:    la consulta, con %s como marcador de cada valor variable
              (nunca se debe meter el valor directo en el texto del SQL:
              eso es lo que abre la puerta a "inyección SQL").
    - params: tupla con los valores que reemplazan cada %s, en orden.
    - uno:    True si se espera una sola fila (ej. buscar por correo),
              False si se espera una lista (ej. listar productos).

    El "try/finally" garantiza que conn.close() se ejecute siempre,
    incluso si cursor.execute() lanza un error, para no dejar la
    conexión a MySQL abierta (eso acaba agotando las conexiones
    disponibles del servidor).
    """
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params)
        return cursor.fetchone() if uno else cursor.fetchall()
    finally:
        conn.close()


def _ejecutar(sql, params=()):
    """
    Igual que _consulta, pero para INSERT / UPDATE / DELETE: sentencias
    que cambian datos en vez de leerlos.

    Devuelve una tupla (filas_afectadas, id_generado):
      - filas_afectadas: cuántas filas tocó la sentencia (útil para saber
        si un DELETE realmente borró algo, o si buscaba un id que no existe).
      - id_generado: el id autoincremental que MySQL asignó, solo tiene
        sentido después de un INSERT (en un UPDATE/DELETE viene vacío).

    conn.commit() confirma los cambios: sin esto, MySQL los guardaría
    solo temporalmente y se perderían al cerrar la conexión.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        conn.commit()
        return cursor.rowcount, cursor.lastrowid
    finally:
        conn.close()


def _entero(valor, minimo, maximo=None):
    """
    Convierte 'valor' (que puede venir como texto, número o algo raro
    desde el JSON del cliente) a un número entero válido.

    Devuelve None si:
      - no se puede convertir a entero (ej. "abc"), o
      - el número queda fuera del rango [minimo, maximo].

    Se usa así en las rutas: "si _entero(...) devuelve None, es que el
    dato no sirve, y se responde con un error 400 explicando por qué".
    """
    try:
        n = int(valor)
    except (TypeError, ValueError):
        return None
    if n < minimo or (maximo is not None and n > maximo):
        return None
    return n


def _decimal(valor, minimo=0.0):
    """
    Igual que _entero, pero para precios (números con decimales).

    math.isfinite(x) descarta valores como infinito o "NaN" (que técnicamente
    son floats válidos en Python, pero no tienen sentido como precio).
    round(x, 2) redondea a 2 decimales, como cualquier precio en dólares.
    """
    try:
        x = float(valor)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(x) or x < minimo:
        return None
    return round(x, 2)


def _usuario_publico(u):
    """
    Convierte una fila de la tabla 'usuarios' (un diccionario con TODAS
    las columnas, incluida la contraseña con hash) en la versión que sí
    es segura mandar a la app: sin la columna 'password'.

    Esto se llama justo antes de cada jsonify() que incluya datos de un
    usuario, para no exponer el hash de la contraseña por accidente.
    """
    return {
        "id": u.get("id"),
        "usuario": u.get("usuario"),
        "nombres": u.get("nombres"),
        "apellidos": u.get("apellidos"),
        "correo": u.get("correo"),
        "edad": u.get("edad"),
        "rol": u.get("rol"),
    }


def _producto_publico(p):
    """Da forma consistente y tolerante a datos antiguos del catálogo."""
    return {
        "id": int(p["id"]),
        "nombre": str(p.get("nombre") or ""),
        "cantidad": int(p.get("cantidad") or 0),
        "precio": float(p.get("precio") or 0),
        # 40 cm mantiene compatibilidad con filas creadas antes de esta columna.
        "tamano_tallo_cm": int(p.get("tamano_tallo_cm") or 40),
        "imagen_url": p.get("imagen_url"),
    }


def _paginacion():
    """
    Lee ?pagina=N&por_pagina=M de la URL del pedido (ej. GET
    /api/productos?pagina=2&por_pagina=10) y los convierte en el LIMIT/OFFSET
    que MySQL necesita.

    Por qué esto es "optimización" (punto 5 de la guía del proyecto):
    sin paginación, /api/productos siempre traería TODAS las filas de la
    tabla en una sola respuesta. Con 20 productos no se nota, pero con
    5 000 sería una respuesta enorme, lenta de generar en el servidor,
    lenta de mandar por la red, y lenta de dibujar en el teléfono. Con
    LIMIT/OFFSET, cada pedido solo trae la "página" que se va a mostrar.

    - pagina: empieza en 1 (no en 0), por ser más natural para la UI.
    - por_pagina: cuántas filas trae cada página; con un tope de 50 para
      que nadie pida, por accidente o a propósito, una página gigante.
    """
    pagina = _entero(request.args.get("pagina", 1), 1) or 1
    por_pagina = _entero(request.args.get("por_pagina", 10), 1, 50) or 10
    offset = (pagina - 1) * por_pagina
    return pagina, por_pagina, offset


def _serializer():
    """
    Crea el objeto que firma y verifica los tokens de sesión.

    - current_app.secret_key: la misma clave secreta que usa Flask para
      firmar las cookies de sesión de la web (viene del .env). Si esta
      clave cambiara, todos los tokens ya emitidos dejarían de ser válidos.
    - salt="floricola-api-token": una "sal" extra, para que un token hecho
      para esta API nunca se pueda confundir con una firma usada en otra
      parte de la app que use la misma secret_key con otro propósito.
    """
    return URLSafeTimedSerializer(current_app.secret_key, salt="floricola-api-token")


# ======================================================================
# PROTECCIÓN DE RUTAS (decoradores)
# ======================================================================
# Un decorador (@algo encima de una función) es una forma de "envolver"
# una función con código que se ejecuta antes o después de ella, sin
# tener que repetir ese código en cada ruta. Aquí se usan dos:
#   @requiere_token  -> exige un token de sesión válido
#   @requiere_admin  -> exige token válido Y que el usuario sea admin

def requiere_token(f):
    """
    Decorador que protege una ruta detrás de un login válido.

    Uso:
        @api_bp.get("/algo")
        @requiere_token
        def mi_ruta():
            ...  # aquí ya se puede usar g.usuario

    Qué hace paso a paso:
      1. Busca la cabecera "Authorization" en el pedido HTTP.
      2. Debe empezar con "Bearer " (el estándar para tokens); si no,
         no hay token -> error 401 (no autenticado).
      3. Intenta abrir el token con el mismo 'salt' con el que se firmó.
         - Si pasó más de TOKEN_DURACION desde que se creó -> "expiró".
         - Si la firma no coincide (token falso o corrupto) -> "inválida".
      4. Si el token es válido, contiene el correo del usuario: se busca
         ese usuario en la base de datos por si fue borrado.
      5. Se guarda el usuario encontrado en 'g.usuario'. 'g' es un espacio
         de Flask que dura solo durante ESTE pedido: cualquier función
         llamada después (incluida la ruta real) puede leer g.usuario
         sin que ese dato se mezcle con el de otro usuario que esté
         usando la app al mismo tiempo.
    """
    @wraps(f)  # conserva el nombre/doc de la función original (buena práctica con decoradores)
    def wrapper(*args, **kwargs):
        cabecera = request.headers.get("Authorization", "")
        if not cabecera.startswith("Bearer "):
            return _error("Falta el token de sesión", 401)

        try:
            # cabecera[7:] quita el texto "Bearer " (7 caracteres) y deja solo el token
            datos = _serializer().loads(cabecera[7:], max_age=TOKEN_DURACION)
        except SignatureExpired:
            return _error("La sesión expiró, inicia sesión otra vez", 401)
        except BadSignature:
            return _error("Sesión inválida", 401)

        usuario = _consulta(
            "SELECT * FROM usuarios WHERE correo = %s", (datos.get("correo"),), uno=True
        )
        if not usuario:
            return _error("Usuario no encontrado", 401)

        g.usuario = usuario
        return f(*args, **kwargs)  # ya validado: se ejecuta la ruta real

    return wrapper


def requiere_admin(f):
    """
    Como @requiere_token, pero además exige rol == "admin".

    Truco: en vez de repetir la lógica del token, esta función envuelve
    'f' con la comprobación de admin y LUEGO pasa ese resultado por
    requiere_token(...). Así el orden real de ejecución es:
        1) valida el token (pone g.usuario)
        2) revisa que g.usuario sea admin
        3) recién ahí llama a la función de la ruta

    Se usa en las rutas donde solo el administrador debe poder actuar,
    como agregar o eliminar productos, o ver la lista de clientes.
    """
    @wraps(f)
    def wrapper(*args, **kwargs):
        if g.usuario.get("rol") != "admin":
            return _error("Solo el administrador puede hacer esto", 403)
        return f(*args, **kwargs)

    return requiere_token(wrapper)


@api_bp.errorhandler(Exception)
def _error_generico(e):
    """
    Red de seguridad: si cualquier ruta de /api/... lanza un error que
    nadie manejó explícitamente (una excepción de Python cualquiera),
    esta función lo intercepta para que la app SIEMPRE reciba JSON
    (y no una página de error HTML de Flask, que Flutter no sabría leer).

    - Si es un error "esperado" de Flask/Werkzeug (HTTPException, como
      404 o 405), se respeta su código y mensaje.
    - Si es un error inesperado (un bug), se registra el detalle completo
      en el log del servidor (current_app.logger.exception) para que el
      desarrollador lo vea, pero al cliente solo se le dice "Error interno
      del servidor": nunca se debe mostrar el detalle técnico interno
      (rutas de archivos, consultas SQL, etc.) a quien usa la app.
    """
    if isinstance(e, HTTPException):
        return _error(e.description, e.code)
    current_app.logger.exception("Error en la API")
    return _error("Error interno del servidor", 500)


# ======================================================================
# CORREO Y VALIDACIÓN DE CONTRASEÑAS
# ======================================================================

PASSWORD_RE = re.compile(r"^(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,64}$")

# Limitador sencillo por IP para frenar intentos automatizados. Es deliberadamente
# pequeño y en memoria: para varios procesos/servidores conviene Redis o un proxy.
_RATE_LIMIT = {}

def _limitar_intentos(nombre, limite, ventana_segundos):
    ahora = time.monotonic()
    ip = request.remote_addr or "desconocida"
    clave = (nombre, ip)
    intentos = [t for t in _RATE_LIMIT.get(clave, []) if ahora - t < ventana_segundos]
    if len(intentos) >= limite:
        return _error("Demasiados intentos. Espera unos minutos y vuelve a intentarlo.", 429)
    intentos.append(ahora)
    _RATE_LIMIT[clave] = intentos
    # Limpieza ocasional de claves antiguas.
    if len(_RATE_LIMIT) > 5000:
        for k in list(_RATE_LIMIT):
            _RATE_LIMIT[k] = [t for t in _RATE_LIMIT[k] if ahora - t < ventana_segundos]
            if not _RATE_LIMIT[k]:
                del _RATE_LIMIT[k]
    return None

def _producto_publico_defensivo(p):
    return {
        "id": int(p["id"]),
        "nombre": str(p.get("nombre") or ""),
        "cantidad": int(p.get("cantidad") or 0),
        "precio": float(p.get("precio") or 0),
        "tamano_tallo_cm": int(p.get("tamano_tallo_cm") or 40),
        "imagen_url": p.get("imagen_url"),
    }


def _password_valida(password):
    return isinstance(password, str) and bool(PASSWORD_RE.fullmatch(password))


def _enviar_correo(destinatario, asunto, cuerpo, adjunto=None, nombre_adjunto=None):
    host = os.environ.get("SMTP_HOST")
    port = int(os.environ.get("SMTP_PORT", "587"))
    usuario = os.environ.get("SMTP_USER")
    password = "".join(os.environ.get("SMTP_PASSWORD", "").split())
    remitente = os.environ.get("SMTP_FROM") or usuario
    if not host or not usuario or not password or not remitente:
        raise RuntimeError("Falta configurar SMTP_HOST, SMTP_USER, SMTP_PASSWORD o SMTP_FROM")

    msg = EmailMessage()
    msg["From"] = remitente
    msg["To"] = destinatario
    msg["Subject"] = asunto
    msg.set_content(cuerpo)
    if adjunto is not None:
        msg.add_attachment(adjunto, maintype="application", subtype="pdf", filename=nombre_adjunto or "comprobante.pdf")

    with smtplib.SMTP(host, port, timeout=20) as smtp:
        if os.environ.get("SMTP_STARTTLS", "1") == "1":
            smtp.starttls()
        smtp.login(usuario, password)
        smtp.send_message(msg)


def _codigo_verificacion():
    return f"{secrets.randbelow(1000000):06d}"


def _crear_verificacion(usuario_id, correo, correo_destino=None):
    codigo = _codigo_verificacion()
    _ejecutar("DELETE FROM verificaciones_email WHERE usuario_id = %s", (usuario_id,))
    _ejecutar(
        """
        INSERT INTO verificaciones_email
            (usuario_id, correo_destino, codigo, expiracion, usado)
        VALUES (%s, %s, %s, %s, FALSE)
        """,
        (
            usuario_id,
            correo_destino or correo,
            codigo,
            datetime.now() + timedelta(minutes=15),
        ),
    )
    _enviar_correo(
        correo_destino or correo,
        "Verifica tu correo - Florícola Los Álamos",
        f"Hola,\n\nTu código de verificación es: {codigo}\n\nEl código vence en 15 minutos. Si no solicitaste esta cuenta, puedes ignorar este mensaje.\n\nFlorícola Los Álamos",
    )


def _hash_codigo_recuperacion(codigo):
    clave = current_app.secret_key
    if isinstance(clave, str):
        clave = clave.encode("utf-8")
    if not clave:
        raise RuntimeError("SECRET_KEY debe estar configurada para recuperar contraseñas")
    return hmac.new(clave, codigo.encode("utf-8"), hashlib.sha256).hexdigest()


def _restablecer_password(correo, codigo, nueva_password):
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT id
            FROM usuarios
            WHERE correo = %s AND email_verificado = TRUE
            FOR UPDATE
            """,
            (correo,),
        )
        usuario = cursor.fetchone()
        if not usuario:
            conn.rollback()
            return False

        cursor.execute(
            """
            SELECT codigo_hash, intentos, usado,
                   (expiracion > %s) AS vigente
            FROM codigos_recuperacion
            WHERE usuario_id = %s
            FOR UPDATE
            """,
            (datetime.now(), usuario["id"]),
        )
        recuperacion = cursor.fetchone()
        if not recuperacion or recuperacion["usado"] or not recuperacion["vigente"]:
            conn.rollback()
            return False

        if recuperacion["intentos"] >= 5:
            conn.rollback()
            return False

        codigo_valido = secrets.compare_digest(
            recuperacion["codigo_hash"],
            _hash_codigo_recuperacion(codigo),
        )
        if not codigo_valido:
            cursor.execute(
                """
                UPDATE codigos_recuperacion
                SET intentos = intentos + 1
                WHERE usuario_id = %s
                """,
                (usuario["id"],),
            )
            conn.commit()
            return False

        cursor.execute(
            "UPDATE usuarios SET password = %s WHERE id = %s",
            (hash_password(nueva_password), usuario["id"]),
        )
        cursor.execute(
            """
            UPDATE codigos_recuperacion
            SET usado = TRUE
            WHERE usuario_id = %s
            """,
            (usuario["id"],),
        )
        conn.commit()
        return True
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ======================================================================
# SESIÓN: registrarse, iniciar sesión, ver mis datos
# ======================================================================

@api_bp.post("/login")
def login():
    limitado = _limitar_intentos("login", 10, 60)
    if limitado:
        return limitado
    """
    POST /api/login
    Entrada (JSON):  { "correo": "...", "password": "..." }
    Salida (200):    { "token": "...", "usuario": {...} }
    Salida (error):  { "error": "..." } con 400 o 401

    Es la puerta de entrada de la app: si las credenciales son correctas,
    devuelve un token que la app deberá guardar y reenviar en cada pedido
    posterior (ver la explicación de tokens al inicio del archivo).
    """
    datos = request.get_json(silent=True) or {}
    # silent=True: si el cuerpo no es JSON válido, get_json no lanza error,
    # devuelve None, y el "or {}" evita que el resto del código truene.
    correo = str(datos.get("correo", "")).strip().lower()
    password = str(datos.get("password", ""))

    if not correo or not password:
        return _error("Ingresa tu correo y contraseña")

    usuario = _consulta("SELECT * FROM usuarios WHERE correo = %s", (correo,), uno=True)

    # verificar_password compara la contraseña ingresada contra la guardada,
    # sea que esté en hash (cuentas nuevas) o en texto plano (cuentas viejas).
    # Si 'usuario' es None (el correo no existe), se le pasa None: la función
    # está preparada para decir "no coincide" sin lanzar un error.
    ok, actualizar = verificar_password(usuario["password"] if usuario else None, password)

    if not ok:
        # A propósito NO se distingue "correo no existe" de "clave incorrecta":
        # si se distinguiera, alguien podría usar el login para averiguar
        # qué correos están registrados, probando uno por uno.
        return _error("Credenciales incorrectas", 401)

    if actualizar:
        # 'actualizar' es True solo cuando la cuenta todavía tenía la
        # contraseña en texto plano (de antes de este proyecto) y la
        # clave ingresada fue correcta: se aprovecha este login para
        # migrarla a hash de forma silenciosa, sin que el usuario note nada.
        try:
            _ejecutar(
                "UPDATE usuarios SET password = %s WHERE correo = %s",
                (hash_password(password), usuario["correo"]),
            )
        except Exception:
            # Si la columna 'password' es demasiado corta para un hash
            # (~255 caracteres) esto puede fallar. No se interrumpe el
            # login por eso: solo se avisa en el log para que el
            # desarrollador corra migracion.sql.
            current_app.logger.warning(
                "No se pudo actualizar a hash (¿la columna password es muy corta? "
                "Ejecuta migracion.sql)"
            )

    if not usuario.get("email_verificado", True):
        return _error("Debes verificar tu correo electrónico antes de iniciar sesión", 403)

    # El token solo lleva el correo: es la mínima información necesaria
    # para, en cada pedido futuro, volver a buscar el usuario completo.
    token = _serializer().dumps({"correo": usuario["correo"]})
    return jsonify({"token": token, "usuario": _usuario_publico(usuario)})


@api_bp.post("/password/recuperar")
def solicitar_recuperacion_password():
    limitado = _limitar_intentos("recuperar-password", 5, 600)
    if limitado:
        return limitado

    datos = request.get_json(silent=True) or {}
    correo = str(datos.get("correo", "")).strip().lower()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", correo):
        return _error("Ingresa un correo válido")

    respuesta = {
        "mensaje": (
            "Si existe una cuenta verificada con ese correo, "
            "recibirás un código para restablecer la contraseña."
        )
    }
    usuario = _consulta(
        "SELECT id FROM usuarios WHERE correo = %s AND email_verificado = TRUE",
        (correo,),
        uno=True,
    )
    if not usuario:
        return jsonify(respuesta)

    codigo = _codigo_verificacion()
    _ejecutar(
        """
        INSERT INTO codigos_recuperacion
            (usuario_id, codigo_hash, expiracion, intentos, usado)
        VALUES (%s, %s, %s, 0, FALSE)
        ON DUPLICATE KEY UPDATE
            codigo_hash = VALUES(codigo_hash),
            expiracion = VALUES(expiracion),
            intentos = 0,
            usado = FALSE
        """,
        (
            usuario["id"],
            _hash_codigo_recuperacion(codigo),
            datetime.now() + timedelta(minutes=15),
        ),
    )
    try:
        _enviar_correo(
            correo,
            "Recupera tu contraseña - Florícola Los Álamos",
            f"Tu código para cambiar la contraseña es: {codigo}\n\n"
            "El código vence en 15 minutos y solo se puede usar una vez. "
            "Si no solicitaste este cambio, ignora este mensaje.",
        )
    except (OSError, RuntimeError, ValueError, smtplib.SMTPException):
        current_app.logger.exception(
            "No se pudo enviar el código de recuperación de contraseña"
        )
    return jsonify(respuesta)


@api_bp.post("/password/restablecer")
def restablecer_password():
    limitado = _limitar_intentos("restablecer-password", 10, 600)
    if limitado:
        return limitado

    datos = request.get_json(silent=True) or {}
    correo = str(datos.get("correo", "")).strip().lower()
    codigo = str(datos.get("codigo", "")).strip()
    nueva_password = datos.get("nueva_password", "")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", correo):
        return _error("Ingresa un correo válido")
    if not re.fullmatch(r"\d{6}", codigo):
        return _error("El código debe tener 6 dígitos")
    if not _password_valida(nueva_password):
        return _error(
            "La contraseña debe tener entre 8 y 64 caracteres, "
            "una mayúscula, un número y un signo especial"
        )

    if not _restablecer_password(correo, codigo, nueva_password):
        return _error("El código es incorrecto, venció o ya fue utilizado", 400)
    return jsonify({"mensaje": "Contraseña actualizada. Ya puedes iniciar sesión."})


@api_bp.post("/registro")
def registro():
    limitado = _limitar_intentos("registro", 5, 600)
    if limitado:
        return limitado
    """
    POST /api/registro
    Entrada (JSON): { "nombres", "apellidos", "correo", "password", "edad" }
    Salida (201):   { "mensaje": "Cuenta creada" }

    Crea una cuenta nueva con rol "cliente" (el rol "admin" nunca se
    asigna desde la app: se cambia a mano en la base de datos, ver README).
    Todas las validaciones ocurren ANTES de tocar la base de datos, para
    no dejar filas a medias ni hacer consultas innecesarias.
    """
    datos = request.get_json(silent=True) or {}

    nombres = str(datos.get("nombres", "")).strip()
    apellidos = str(datos.get("apellidos", "")).strip()
    correo = str(datos.get("correo", "")).strip().lower()
    password = str(datos.get("password", ""))
    edad = _entero(datos.get("edad", 20), 1, 120)

    if not nombres or not apellidos:
        return _error("Ingresa tus nombres y apellidos")
    if "@" not in correo or "." not in correo.split("@")[-1]:
        # Validación simple, no perfecta: solo exige un "@" y un "." después
        # de él. Verificar un correo real de verdad requeriría mandar un
        # mensaje de confirmación, fuera del alcance de este proyecto.
        return _error("El correo no es válido")
    if not _password_valida(password):
        return _error("La contraseña debe tener entre 8 y 64 caracteres, una mayúscula, un número y un signo especial")
    if edad is None:
        return _error("La edad debe estar entre 1 y 120")

    if _consulta("SELECT correo FROM usuarios WHERE correo = %s", (correo,), uno=True):
        # 409 Conflict: el pedido está bien formado, pero choca con algo
        # que ya existe (aquí, un correo duplicado).
        return _error("Usuario ya registrado", 409)

    _, nuevo_id = _ejecutar(
        """
        INSERT INTO usuarios (usuario, nombres, apellidos, correo, edad, password, rol, email_verificado)
        VALUES (%s, %s, %s, %s, %s, %s, %s, FALSE)
        """,
        (correo, nombres, apellidos, correo, edad, hash_password(password), "cliente"),
    )
    try:
        _crear_verificacion(nuevo_id, correo)
    except Exception:
        _ejecutar("DELETE FROM usuarios WHERE id = %s", (nuevo_id,))
        current_app.logger.exception("No se pudo enviar el correo de verificación")
        return _error("No se pudo enviar el correo de verificación. Revisa la configuración SMTP del servidor.", 503)
    return jsonify({"mensaje": "Cuenta creada. Revisa tu correo para verificarla.", "correo": correo}), 201


@api_bp.post("/verificar-email")
def verificar_email():
    limitado = _limitar_intentos("verificar-email", 5, 600)
    if limitado:
        return limitado
    datos = request.get_json(silent=True) or {}
    correo = str(datos.get("correo", "")).strip().lower()
    codigo = str(datos.get("codigo", "")).strip()
    if not correo or not re.fullmatch(r"\d{6}", codigo):
        return _error("Correo o código inválido")

    ver = _consulta(
        """
        SELECT id, usuario_id, correo_destino
        FROM verificaciones_email
        WHERE correo_destino = %s AND codigo = %s
          AND usado = FALSE AND expiracion > NOW()
        ORDER BY id DESC LIMIT 1
        """,
        (correo, codigo),
        uno=True,
    )
    correo_cambiado = False
    correo_anterior = None
    if ver:
        usuario = _consulta(
            "SELECT * FROM usuarios WHERE id = %s",
            (ver["usuario_id"],),
            uno=True,
        )
        if not usuario:
            return _error("No existe la cuenta asociada al código", 404)
        if usuario["correo"] != correo:
            correo_anterior = usuario["correo"]
            existente = _consulta(
                "SELECT id FROM usuarios WHERE correo = %s",
                (correo,),
                uno=True,
            )
            if existente:
                return _error("Ese correo ya está asociado a otra cuenta", 409)
            _ejecutar(
                "UPDATE usuarios SET correo = %s, email_verificado = TRUE WHERE id = %s",
                (correo, usuario["id"]),
            )
            correo_cambiado = True
    else:
        usuario = _consulta(
            "SELECT * FROM usuarios WHERE correo = %s",
            (correo,),
            uno=True,
        )
    if not usuario:
        return _error("No existe una cuenta con ese correo", 404)
    if usuario.get("email_verificado") and not ver:
        return jsonify({"mensaje": "El correo ya está verificado"})

    if not ver:
        ver = _consulta(
            """
            SELECT id, usuario_id, correo_destino
            FROM verificaciones_email
            WHERE usuario_id = %s AND codigo = %s
              AND usado = FALSE AND expiracion > NOW()
            ORDER BY id DESC LIMIT 1
            """,
            (usuario["id"], codigo),
            uno=True,
        )
    if not ver:
        return _error("Código incorrecto o vencido", 400)
    if not correo_cambiado:
        _ejecutar("UPDATE usuarios SET email_verificado = TRUE WHERE id = %s", (usuario["id"],))
    _ejecutar("UPDATE verificaciones_email SET usado = TRUE WHERE id = %s", (ver["id"],))
    respuesta = {"mensaje": "Correo verificado correctamente"}
    if correo_cambiado:
        usuario = _consulta(
            "SELECT * FROM usuarios WHERE id = %s",
            (usuario["id"],),
            uno=True,
        )
        autorizacion = request.headers.get("Authorization", "")
        try:
            token_payload = _serializer().loads(
                autorizacion[7:],
                max_age=TOKEN_DURACION,
            ) if autorizacion.startswith("Bearer ") else {}
        except (BadSignature, SignatureExpired):
            token_payload = {}
        if token_payload.get("correo") == correo_anterior:
            respuesta.update({
                "token": _serializer().dumps({"correo": usuario["correo"]}),
                "usuario": _usuario_publico(usuario),
            })
    return jsonify(respuesta)


@api_bp.post("/reenviar-verificacion")
def reenviar_verificacion():
    limitado = _limitar_intentos("reenviar-verificacion", 3, 600)
    if limitado:
        return limitado
    datos = request.get_json(silent=True) or {}
    correo = str(datos.get("correo", "")).strip().lower()
    pendiente = _consulta(
        """
        SELECT usuario_id
        FROM verificaciones_email
        WHERE correo_destino = %s
        ORDER BY id DESC LIMIT 1
        """,
        (correo,),
        uno=True,
    )
    usuario = (
        _consulta("SELECT * FROM usuarios WHERE id = %s", (pendiente["usuario_id"],), uno=True)
        if pendiente
        else _consulta("SELECT * FROM usuarios WHERE correo = %s", (correo,), uno=True)
    )
    if not usuario:
        return _error("No existe una cuenta con ese correo", 404)
    if usuario["correo"] == correo and usuario.get("email_verificado"):
        return _error("El correo ya está verificado")
    try:
        _crear_verificacion(usuario["id"], usuario["correo"], correo)
    except Exception:
        current_app.logger.exception("No se pudo reenviar el correo de verificación")
        return _error("No se pudo enviar el correo de verificación", 503)
    return jsonify({"mensaje": "Código reenviado"})


@api_bp.get("/me")
@requiere_token
def me():
    """
    GET /api/me
    Requiere: Authorization: Bearer <token>
    Salida:   los datos del usuario dueño del token (sin la contraseña)

    Lo usa la app al abrirse: si hay un token guardado en el teléfono,
    pregunta aquí "¿sigue siendo válido, y quién es este usuario?" en
    vez de pedirle que vuelva a escribir su correo y contraseña.
    """
    usuario = _usuario_publico(g.usuario)
    pendiente = _consulta(
        """
        SELECT correo_destino
        FROM verificaciones_email
        WHERE usuario_id = %s AND correo_destino <> %s
        ORDER BY id DESC LIMIT 1
        """,
        (g.usuario["id"], g.usuario["correo"]),
        uno=True,
    )
    if pendiente:
        usuario["correo_pendiente"] = pendiente["correo_destino"]
    return jsonify(usuario)


def _actualizar_perfil(usuario_id, datos):
    usuario = _consulta("SELECT * FROM usuarios WHERE id = %s", (usuario_id,), uno=True)
    if not usuario:
        return _error("No existe ese usuario", 404)

    datos = datos if isinstance(datos, dict) else {}
    nombre_usuario = str(datos.get("usuario", "")).strip()
    nombres = str(datos.get("nombres", "")).strip()
    apellidos = str(datos.get("apellidos", "")).strip()
    correo = str(datos.get("correo", "")).strip().lower()
    edad = _entero(datos.get("edad"), 1, 120)

    if not nombre_usuario or len(nombre_usuario) > 100:
        return _error("El nombre de usuario es obligatorio y admite hasta 100 caracteres")
    if not nombres or len(nombres) > 100:
        return _error("Los nombres son obligatorios y admiten hasta 100 caracteres")
    if not apellidos or len(apellidos) > 100:
        return _error("Los apellidos son obligatorios y admiten hasta 100 caracteres")
    if len(correo) > 150 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", correo):
        return _error("El correo no es válido")
    if edad is None:
        return _error("La edad debe estar entre 1 y 120")

    correo_cambio = correo != usuario["correo"]
    if correo_cambio and _consulta(
        "SELECT id FROM usuarios WHERE correo = %s AND id <> %s",
        (correo, usuario_id),
        uno=True,
    ):
        return _error("Ese correo ya está asociado a otra cuenta", 409)

    _ejecutar(
        """
        UPDATE usuarios
        SET usuario = %s, nombres = %s, apellidos = %s, edad = %s
        WHERE id = %s
        """,
        (nombre_usuario, nombres, apellidos, edad, usuario_id),
    )

    correo_pendiente = None
    if correo_cambio:
        try:
            _crear_verificacion(usuario_id, usuario["correo"], correo)
            correo_pendiente = correo
        except Exception:
            current_app.logger.exception(
                "Se guardó el perfil, pero no se pudo enviar la verificación del nuevo correo"
            )
            return _error(
                "Los datos se guardaron, pero no se pudo enviar el código al nuevo correo. "
                "Solicita reenviar el código.",
                503,
            )

    usuario_actualizado = _consulta(
        "SELECT * FROM usuarios WHERE id = %s",
        (usuario_id,),
        uno=True,
    )
    respuesta = {"usuario": _usuario_publico(usuario_actualizado)}
    if correo_pendiente:
        respuesta["correo_pendiente"] = correo_pendiente
        respuesta["usuario"]["correo_pendiente"] = correo_pendiente
    return jsonify(respuesta)


@api_bp.put("/me")
@requiere_token
def actualizar_mi_perfil():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return _error("Envía los datos del perfil en formato JSON")
    return _actualizar_perfil(g.usuario["id"], datos)


@api_bp.put("/clientes/<int:usuario_id>")
@requiere_admin
def actualizar_cliente(usuario_id):
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return _error("Envía los datos del perfil en formato JSON")
    return _actualizar_perfil(usuario_id, datos)


# ======================================================================
# PRODUCTOS (INVENTARIO)
# ======================================================================

@api_bp.get("/productos")
@requiere_token
def listar_productos():
    """Lista el catálogo con nombre, datos e imagen opcional."""
    _, por_pagina, offset = _paginacion()
    buscar = (request.args.get("buscar") or "").strip()

    condicion = ""
    parametros = ()
    if buscar:
        condicion = "WHERE nombre LIKE %s"
        parametros = (f"%{buscar}%",)

    filas = _consulta(
        f"SELECT id, nombre, cantidad, precio, tamano_tallo_cm, imagen_url FROM productos {condicion} "
        f"ORDER BY nombre LIMIT %s OFFSET %s",
        parametros + (por_pagina, offset),
    )
    total = _consulta(
        f"SELECT COUNT(*) AS total FROM productos {condicion}", parametros, uno=True
    )["total"]

    return jsonify({
        "datos": [_producto_publico(p) for p in filas],
        "total": total,
        "por_pagina": por_pagina,
    })


@api_bp.get("/productos/imagenes/<path:nombre_archivo>")
def imagen_producto(nombre_archivo):
    """Sirve públicamente una foto del catálogo."""
    nombre_seguro = os.path.basename(nombre_archivo)
    return send_from_directory(_carpeta_imagenes_productos(), nombre_seguro)


@api_bp.get("/inicio/contenido")
@requiere_token
def contenido_inicio():
    return jsonify(_contenido_inicio())


@api_bp.get("/inicio/imagenes/<path:nombre_archivo>")
def imagen_inicio(nombre_archivo):
    nombre_seguro = os.path.basename(nombre_archivo)
    if not re.fullmatch(
        r"(?:fondo|galeria)_[0-9a-f]{32}\.(?:jpg|jpeg|png|webp)",
        nombre_seguro,
    ):
        return _error("La imagen solicitada no existe", 404)
    return send_from_directory(_carpeta_inicio(), nombre_seguro)


@api_bp.post("/inicio/fondo")
@requiere_admin
def subir_fondo_inicio():
    contenido = _contenido_inicio()
    nuevo_fondo = _guardar_imagen_inicio(request.files.get("imagen"), "fondo")
    anterior = contenido["fondo"]
    contenido["fondo"] = nuevo_fondo
    try:
        _guardar_contenido_inicio(contenido)
    except Exception:
        _borrar_imagen_inicio(nuevo_fondo)
        raise
    if anterior:
        _borrar_imagen_inicio(anterior)
    return jsonify({"fondo": nuevo_fondo})


@api_bp.delete("/inicio/fondo")
@requiere_admin
def quitar_fondo_inicio():
    contenido = _contenido_inicio()
    anterior = contenido["fondo"]
    contenido["fondo"] = None
    _guardar_contenido_inicio(contenido)
    if anterior:
        _borrar_imagen_inicio(anterior)
    return jsonify({"mensaje": "Fondo eliminado"})


@api_bp.post("/inicio/galeria")
@requiere_admin
def agregar_imagen_inicio():
    contenido = _contenido_inicio()
    if len(contenido["galeria"]) >= MAX_IMAGENES_INICIO:
        return _error(f"La galería admite hasta {MAX_IMAGENES_INICIO} imágenes", 400)

    nombre = _guardar_imagen_inicio(request.files.get("imagen"), "galeria")
    contenido["galeria"].append(nombre)
    try:
        _guardar_contenido_inicio(contenido)
    except Exception:
        _borrar_imagen_inicio(nombre)
        raise
    return jsonify({"galeria": contenido["galeria"]}), 201


@api_bp.delete("/inicio/galeria/<path:nombre_archivo>")
@requiere_admin
def quitar_imagen_inicio(nombre_archivo):
    nombre_seguro = os.path.basename(nombre_archivo)
    contenido = _contenido_inicio()
    if nombre_seguro not in contenido["galeria"]:
        return _error("La imagen no existe en la galería", 404)

    contenido["galeria"].remove(nombre_seguro)
    _guardar_contenido_inicio(contenido)
    _borrar_imagen_inicio(nombre_seguro)
    return jsonify({"galeria": contenido["galeria"]})


@api_bp.put("/productos/<int:producto_id>")
@requiere_admin
def actualizar_producto(producto_id):
    """Actualiza datos del producto y, si se envía, reemplaza su imagen."""
    es_multipart = request.content_type and request.content_type.startswith("multipart/form-data")
    datos = request.form if es_multipart else (request.get_json(silent=True) or {})

    nombre = str(datos.get("nombre", "")).strip()
    cantidad = _entero(datos.get("cantidad"), 0)
    precio = _decimal(datos.get("precio"))
    tallo_cm = _entero(datos.get("tamano_tallo_cm"), 1, 200)

    if not nombre:
        return _error("Ingresa el nombre del producto")
    if cantidad is None:
        return _error("La cantidad debe ser un número entero, 0 o mayor")
    if precio is None:
        return _error("El precio debe ser un número, 0 o mayor")
    if tallo_cm is None:
        return _error("El tamaño del tallo debe ser un número entre 1 y 200 cm")

    anterior = _consulta("SELECT imagen_url FROM productos WHERE id = %s", (producto_id,), uno=True)
    if not anterior:
        return _error("El producto no existe", 404)

    archivo = request.files.get("imagen") if es_multipart else None
    nueva_imagen = None
    try:
        if archivo is not None and archivo.filename:
            nueva_imagen = _guardar_imagen_producto(archivo, producto_id)

        imagen_final = nueva_imagen or anterior.get("imagen_url")
        afectadas, _ = _ejecutar(
            "UPDATE productos SET nombre = %s, cantidad = %s, precio = %s, tamano_tallo_cm = %s, imagen_url = %s WHERE id = %s",
            (nombre, cantidad, precio, tallo_cm, imagen_final, producto_id),
        )
        if afectadas == 0:
            if nueva_imagen:
                _borrar_imagen_producto(nueva_imagen)
            return _error("El producto no existe", 404)

        if nueva_imagen and anterior.get("imagen_url") and anterior["imagen_url"] != nueva_imagen:
            _borrar_imagen_producto(anterior["imagen_url"])

        return jsonify({
            "id": producto_id, "nombre": nombre, "cantidad": cantidad,
            "precio": precio, "tamano_tallo_cm": tallo_cm,
            "imagen_url": imagen_final,
        })
    except ValueError as exc:
        return _error(str(exc))
    except Exception:
        if nueva_imagen:
            _borrar_imagen_producto(nueva_imagen)
        raise


@api_bp.post("/productos")
@requiere_admin
def agregar_producto():
    """Crea un producto y guarda una imagen opcional."""
    es_multipart = request.content_type and request.content_type.startswith("multipart/form-data")
    datos = request.form if es_multipart else (request.get_json(silent=True) or {})

    nombre = str(datos.get("nombre", "")).strip()
    cantidad = _entero(datos.get("cantidad"), 0)
    precio = _decimal(datos.get("precio"))
    tallo_cm = _entero(datos.get("tamano_tallo_cm"), 1, 200)

    if not nombre:
        return _error("Ingresa el nombre del producto")
    if cantidad is None:
        return _error("La cantidad debe ser un número entero, 0 o mayor")
    if precio is None:
        return _error("El precio debe ser un número, 0 o mayor")
    if tallo_cm is None:
        return _error("El tamaño del tallo debe ser un número entre 1 y 200 cm")

    _, nuevo_id = _ejecutar(
        "INSERT INTO productos (nombre, cantidad, precio, tamano_tallo_cm, imagen_url) VALUES (%s, %s, %s, %s, %s)",
        (nombre, cantidad, precio, tallo_cm, None),
    )

    archivo = request.files.get("imagen") if es_multipart else None
    imagen = None
    try:
        if archivo is not None and archivo.filename:
            imagen = _guardar_imagen_producto(archivo, nuevo_id)
            _ejecutar("UPDATE productos SET imagen_url = %s WHERE id = %s", (imagen, nuevo_id))
    except ValueError as exc:
        _ejecutar("DELETE FROM productos WHERE id = %s", (nuevo_id,))
        raise_error = _error(str(exc))
        return raise_error
    except Exception:
        if imagen:
            _borrar_imagen_producto(imagen)
        _ejecutar("DELETE FROM productos WHERE id = %s", (nuevo_id,))
        raise

    producto = {
        "id": nuevo_id, "nombre": nombre, "cantidad": cantidad,
        "precio": precio, "tamano_tallo_cm": tallo_cm,
        "imagen_url": imagen,
    }
    return jsonify(producto), 201


@api_bp.delete("/productos/<int:producto_id>")
@requiere_admin
def eliminar_producto(producto_id):
    """
    DELETE /api/productos/<id>
    Solo admin. <int:producto_id> en la ruta hace que Flask solo acepte
    números aquí (una petición a /api/productos/abc daría 404 directamente,
    sin llegar siquiera a ejecutar esta función).
    """
    producto = _consulta("SELECT imagen_url FROM productos WHERE id = %s", (producto_id,), uno=True)
    if not producto:
        return _error("El producto no existe", 404)

    borradas, _ = _ejecutar("DELETE FROM productos WHERE id = %s", (producto_id,))
    if borradas == 0:
        return _error("El producto no existe", 404)
    _borrar_imagen_producto(producto.get("imagen_url"))
    return jsonify({"mensaje": "Producto eliminado"})


# ======================================================================
# CLIENTES (SOLO ADMIN)
# ======================================================================

@api_bp.post("/pedidos")
@requiere_token
def crear_pedido():
    """
    POST /api/pedidos
    Entrada (JSON):
        { "items": [ {"producto_id": 1, "cantidad": 2}, {"producto_id": 3, "cantidad": 1} ] }
    Salida (201): el pedido creado, con sus líneas y su factura.

    Este es el paso "confirmar compra": el carrito que Flutter arma en
    memoria (ver cart_service.dart) se manda completo de una sola vez.
    Aquí, y solo aquí, se crean las filas permanentes en la base de datos.

    Por qué se hace TODO esto en una sola transacción (con commit/rollback
    manual, en vez de usar _consulta/_ejecutar que abren y cierran una
    conexión por cada sentencia): una compra involucra VARIOS cambios que
    deben ocurrir todos juntos o ninguno:
      1. crear el pedido,
      2. crear cada línea de detalle,
      3. descontar el stock de cada producto,
      4. crear la factura.
    Si a mitad de camino algo fallara (por ejemplo, un producto sin stock
    suficiente) y ya se hubiera descontado el stock de uno de los
    productos anteriores, la base de datos quedaría en un estado
    inconsistente (un pedido a medio crear, stock ya descontado de un
    pedido que nunca se completó). Con una transacción: o se confirman
    TODOS los cambios juntos (conn.commit()), o se deshacen TODOS
    (conn.rollback()) apenas se detecta un problema.

    También se vuelve a leer el precio de cada producto DESDE la base de
    datos (nunca del precio que mandara el celular): así nadie puede
    manipular la app para comprar algo más barato de lo que en realidad
    cuesta.
    """
    datos = request.get_json(silent=True) or {}
    items = datos.get("items")

    if not isinstance(items, list) or not items:
        return _error("El pedido no tiene productos")

    # Validar la forma de cada línea ANTES de tocar la base de datos.
    pedido_items = []  # lista de (producto_id, cantidad) ya validados
    for item in items:
        if not isinstance(item, dict):
            return _error("Cada producto del pedido debe ser un objeto")
        producto_id = _entero(item.get("producto_id"), 1)
        cantidad = _entero(item.get("cantidad"), 1)
        if producto_id is None or cantidad is None:
            return _error("Cada producto necesita un id válido y una cantidad mayor a 0")
        pedido_items.append((producto_id, cantidad))

    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        total = 0.0
        lineas = []  # se arma aquí para poder insertarlas después de validar todo

        for producto_id, cantidad in pedido_items:
            # "FOR UPDATE" bloquea la fila del producto hasta que esta
            # transacción termine (commit o rollback). Esto evita una
            # "condición de carrera": si dos personas compraran la
            # última unidad de un producto EXACTAMENTE al mismo tiempo,
            # sin este bloqueo ambas podrían leer "queda 1" y las dos
            # terminarían comprando, dejando el stock en -1.
            cursor.execute(
                "SELECT id, nombre, cantidad, precio FROM productos WHERE id = %s FOR UPDATE",
                (producto_id,),
            )
            producto = cursor.fetchone()
            if not producto:
                conn.rollback()
                return _error(f"El producto {producto_id} no existe", 404)
            if producto["cantidad"] < cantidad:
                conn.rollback()
                return _error(f'No hay suficiente stock de "{producto["nombre"]}"')

            precio_unitario = float(producto["precio"])
            subtotal = round(precio_unitario * cantidad, 2)
            total += subtotal
            lineas.append({
                "producto_id": producto_id,
                "nombre": producto["nombre"],
                "cantidad": cantidad,
                "precio_unitario": precio_unitario,
                "subtotal": subtotal,
            })

        total = round(total, 2)

        # 1) Cabecera del pedido
        cursor.execute(
            "INSERT INTO pedidos (usuario_id, estado, total) VALUES (%s, 'pendiente', %s)",
            (g.usuario["id"], total),
        )
        pedido_id = cursor.lastrowid

        # 2) Una fila de detalle por cada línea, y se descuenta el stock
        for linea in lineas:
            cursor.execute(
                """
                INSERT INTO detalle_pedido
                    (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (pedido_id, linea["producto_id"], linea["cantidad"],
                 linea["precio_unitario"], linea["subtotal"]),
            )
            cursor.execute(
                "UPDATE productos SET cantidad = cantidad - %s WHERE id = %s",
                (linea["cantidad"], linea["producto_id"]),
            )

        # 3) Factura: el número usa el id del pedido, relleno a 6 dígitos
        #    (F-000001, F-000002, ...). Al ser el pedido_id único y
        #    autoincremental, el número de factura también lo es.
        numero_factura = f"F-{pedido_id:06d}"
        cursor.execute(
            "INSERT INTO facturas (pedido_id, numero, total) VALUES (%s, %s, %s)",
            (pedido_id, numero_factura, total),
        )

        conn.commit()  # recién aquí quedan permanentes TODOS los cambios de arriba
    except Exception:
        conn.rollback()
        raise  # el errorhandler general de más arriba lo convierte en un 500 con JSON
    finally:
        conn.close()

    # Devolvemos el pedido con el mismo contrato que usa Pedido.fromJson()
    # en Flutter. La fecha se lee desde MySQL para usar exactamente la
    # fecha/hora que quedó registrada en la cabecera del pedido.
    pedido_creado = _consulta(
        "SELECT fecha FROM pedidos WHERE id = %s", (pedido_id,), uno=True
    )
    if not pedido_creado:
        return _error("No se pudo recuperar el pedido recién creado", 500)

    return jsonify({
        "id": pedido_id,
        "fecha": pedido_creado["fecha"].isoformat(),
        "estado": "pendiente",
        "estado_pago": "pendiente",
        "total": total,
        "items": lineas,
        "factura": {"numero": numero_factura, "total": total},
        "tiene_comprobante": False,
    }), 201


@api_bp.get("/pedidos")
@requiere_token
def listar_pedidos():
    """
    GET /api/pedidos?pagina=1&por_pagina=10&estado=pendiente

    - Un cliente ve solo SUS pedidos (se filtra por g.usuario["id"]).
    - Un admin ve TODOS los pedidos, y puede además filtrar por estado
      con ?estado=pendiente|listo_para_retiro|retirado|cancelado.

    Igual que /api/productos, va paginado: el historial de pedidos de un
    negocio real crece indefinidamente, así que jamás se debe traer
    "todos los pedidos de siempre" en una sola respuesta.
    """
    _, por_pagina, offset = _paginacion()
    estado = (request.args.get("estado") or "").strip()

    condiciones = []
    parametros = []

    if g.usuario.get("rol") == "admin":
        if estado:
            condiciones.append("p.estado = %s")
            parametros.append(estado)
    else:
        # Un cliente jamás puede pedir los pedidos de otra persona:
        # el filtro por usuario_id no depende de nada que mande el
        # celular, solo del usuario que ya identificó el token.
        condiciones.append("p.usuario_id = %s")
        parametros.append(g.usuario["id"])

    where = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""

    filas = _consulta(
        f"""
        SELECT p.id, p.fecha, p.estado, p.estado_pago, p.total, u.nombres, u.apellidos
        FROM pedidos p
        JOIN usuarios u ON u.id = p.usuario_id
        {where}
        ORDER BY p.fecha DESC
        LIMIT %s OFFSET %s
        """,
        tuple(parametros) + (por_pagina, offset),
    )
    total = _consulta(
        f"SELECT COUNT(*) AS total FROM pedidos p {where}", tuple(parametros), uno=True
    )["total"]

    datos = [
        {
            "id": f["id"],
            "fecha": f["fecha"].isoformat(),
            "estado": f["estado"],
            "estado_pago": f["estado_pago"],
            "total": float(f["total"]),
            "cliente": f'{f["nombres"]} {f["apellidos"]}'.strip(),
        }
        for f in filas
    ]
    return jsonify({"datos": datos, "total": total, "por_pagina": por_pagina})


@api_bp.get("/pedidos/<int:pedido_id>")
@requiere_token
def detalle_pedido(pedido_id):
    """
    GET /api/pedidos/<id>
    Devuelve un pedido con todas sus líneas y su factura.

    Un cliente solo puede ver SU PROPIO pedido (si intenta ver el de
    otra persona cambiando el número en la URL, se le responde 404 en
    vez de 403: así ni siquiera se confirma que ese pedido exista, para
    no filtrar información).
    """
    pedido = _consulta(
        """
        SELECT p.id, p.usuario_id, p.fecha, p.estado, p.estado_pago, p.total,
               u.nombres, u.apellidos
        FROM pedidos p JOIN usuarios u ON u.id = p.usuario_id
        WHERE p.id = %s
        """,
        (pedido_id,), uno=True,
    )
    if not pedido:
        return _error("El pedido no existe", 404)

    es_admin = g.usuario.get("rol") == "admin"
    if not es_admin and pedido["usuario_id"] != g.usuario["id"]:
        return _error("El pedido no existe", 404)

    items = _consulta(
        """
        SELECT d.producto_id, pr.nombre, d.cantidad, d.precio_unitario, d.subtotal
        FROM detalle_pedido d JOIN productos pr ON pr.id = d.producto_id
        WHERE d.pedido_id = %s
        """,
        (pedido_id,),
    )
    factura = _consulta(
        "SELECT numero, fecha, total FROM facturas WHERE pedido_id = %s",
        (pedido_id,), uno=True,
    )
    # El comprobante MÁS RECIENTE (puede haber varios si el admin rechazó
    # uno antes): basta con saber si existe, para que Flutter decida si
    # muestra el botón "Ver comprobante". Se ordena por 'id' y no por
    # 'fecha': la fecha solo tiene resolución de segundos, así que dos
    # comprobantes subidos en el mismo segundo empatarían; el id, al ser
    # autoincremental, siempre distingue cuál se insertó después.
    comprobante = _consulta(
        "SELECT id, fecha FROM comprobantes_pago WHERE pedido_id = %s ORDER BY id DESC LIMIT 1",
        (pedido_id,), uno=True,
    )

    return jsonify({
        "id": pedido["id"],
        "fecha": pedido["fecha"].isoformat(),
        "estado": pedido["estado"],
        "estado_pago": pedido["estado_pago"],
        "total": float(pedido["total"]),
        "cliente": f'{pedido["nombres"]} {pedido["apellidos"]}'.strip(),
        "items": [
            {
                "producto_id": i["producto_id"],
                "nombre": i["nombre"],
                "cantidad": i["cantidad"],
                "precio_unitario": float(i["precio_unitario"]),
                "subtotal": float(i["subtotal"]),
            }
            for i in items
        ],
        "factura": None if not factura else {
            "numero": factura["numero"],
            "fecha": factura["fecha"].isoformat(),
            "total": float(factura["total"]),
        },
        "tiene_comprobante": comprobante is not None,
    })


@api_bp.put("/pedidos/<int:pedido_id>/estado")
@requiere_admin
def actualizar_estado_pedido(pedido_id):
    """
    PUT /api/pedidos/<id>/estado
    Entrada: { "estado": "listo_para_retiro" }
    Solo admin: es quien gestiona el avance de un pedido
    (pendiente -> listo_para_retiro -> retirado), o lo cancela.
    """
    datos = request.get_json(silent=True) or {}
    estado = str(datos.get("estado", "")).strip().lower()

    if estado not in ("pendiente", "listo_para_retiro", "retirado", "cancelado"):
        return _error("Estado inválido")

    afectadas, _ = _ejecutar(
        "UPDATE pedidos SET estado = %s WHERE id = %s", (estado, pedido_id)
    )
    if afectadas == 0:
        return _error("El pedido no existe", 404)

    return jsonify({"id": pedido_id, "estado": estado})


@api_bp.delete("/pedidos/<int:pedido_id>")
@requiere_admin
def eliminar_pedido_cancelado(pedido_id):
    """Elimina un pedido cancelado y sus archivos de comprobante. Solo admin."""
    conn = get_connection()
    cursor = None
    comprobantes = []
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT estado FROM pedidos WHERE id = %s FOR UPDATE",
            (pedido_id,),
        )
        pedido = cursor.fetchone()
        if not pedido:
            conn.rollback()
            return _error("El pedido no existe", 404)
        if pedido["estado"] != "cancelado":
            conn.rollback()
            return _error("Solo se pueden eliminar pedidos cancelados", 409)

        cursor.execute(
            "SELECT ruta_archivo FROM comprobantes_pago WHERE pedido_id = %s",
            (pedido_id,),
        )
        comprobantes = cursor.fetchall()
        cursor.execute(
            "DELETE FROM pedidos WHERE id = %s AND estado = 'cancelado'",
            (pedido_id,),
        )
        if cursor.rowcount == 0:
            conn.rollback()
            return _error("El pedido ya no está cancelado", 409)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()

    carpeta_comprobantes = current_app.config["UPLOAD_FOLDER"]
    for comprobante in comprobantes:
        ruta = os.path.join(
            carpeta_comprobantes,
            os.path.basename(comprobante["ruta_archivo"]),
        )
        try:
            if os.path.isfile(ruta):
                os.remove(ruta)
        except OSError:
            current_app.logger.exception(
                "No se pudo eliminar el archivo de comprobante del pedido %s",
                pedido_id,
            )

    return jsonify({"mensaje": "Pedido cancelado eliminado"})


# ======================================================================
# COMPROBANTES DE PAGO (transferencia bancaria)
# ======================================================================

_EXTENSIONES_PERMITIDAS = {"png", "jpg", "jpeg"}


def _extension_valida(nombre_archivo):
    return "." in nombre_archivo and nombre_archivo.rsplit(".", 1)[1].lower() in _EXTENSIONES_PERMITIDAS


@api_bp.post("/pedidos/<int:pedido_id>/comprobante")
@requiere_token
def subir_comprobante(pedido_id):
    """
    POST /api/pedidos/<id>/comprobante
    Entrada: multipart/form-data con un campo de archivo llamado 'imagen'
    (NO es JSON, por eso esta ruta no usa request.get_json).

    Solo el DUEÑO del pedido puede subir su comprobante (no otro cliente,
    ni siquiera el admin: el admin solo REVISA, no sube).

    Qué hace:
      1. Verifica que el pedido exista y sea del usuario.
      2. Verifica que de verdad llegó un archivo, y que su extensión sea
         una imagen permitida (.png, .jpg, .jpeg).
      3. Le pone un nombre único en el servidor (un UUID, no el nombre
         original del archivo) para que dos personas subiendo
         "comprobante.jpg" el mismo día no se pisen una a la otra.
      4. Guarda el archivo en disco, dentro de UPLOAD_FOLDER.
      5. Registra la fila en comprobantes_pago y cambia
         pedidos.estado_pago a 'en_revision'.
    """
    pedido = _consulta(
        "SELECT usuario_id FROM pedidos WHERE id = %s", (pedido_id,), uno=True
    )
    if not pedido:
        return _error("El pedido no existe", 404)
    if pedido["usuario_id"] != g.usuario["id"]:
        return _error("El pedido no existe", 404)

    archivo = request.files.get("imagen")
    if archivo is None or archivo.filename == "":
        return _error("Adjunta una imagen del comprobante")
    if not _extension_valida(archivo.filename):
        return _error("La imagen debe ser .png, .jpg o .jpeg")

    # secure_filename quita caracteres peligrosos del nombre original
    # (como "../" que intentaría escaparse de la carpeta de subidas);
    # el UUID al frente es lo que de verdad evita que se sobrescriban
    # archivos de distintos pedidos o distintas personas.
    extension = archivo.filename.rsplit(".", 1)[1].lower()
    nombre_guardado = f"{pedido_id}_{uuid.uuid4().hex}.{extension}"
    ruta_completa = os.path.join(current_app.config["UPLOAD_FOLDER"], secure_filename(nombre_guardado))
    archivo.save(ruta_completa)

    # El registro del comprobante y el cambio de estado deben quedar en
    # una sola transacción. Si MySQL falla después de guardar el archivo,
    # también eliminamos el archivo para no dejar basura en uploads/.
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO comprobantes_pago (pedido_id, ruta_archivo) VALUES (%s, %s)",
            (pedido_id, nombre_guardado),
        )
        cursor.execute(
            "UPDATE pedidos SET estado_pago = 'en_revision' WHERE id = %s",
            (pedido_id,),
        )
        conn.commit()
    except Exception:
        conn.rollback()
        if os.path.exists(ruta_completa):
            os.remove(ruta_completa)
        raise
    finally:
        conn.close()

    return jsonify({"mensaje": "Comprobante recibido, en revisión"}), 201


@api_bp.get("/pedidos/<int:pedido_id>/comprobante")
@requiere_token
def ver_comprobante(pedido_id):
    """
    GET /api/pedidos/<id>/comprobante
    Devuelve la IMAGEN más reciente del comprobante (no JSON: el propio
    archivo de imagen, para que Flutter lo muestre con Image.memory).

    Solo puede verla el dueño del pedido o un admin (igual que el resto
    del detalle de un pedido).
    """
    pedido = _consulta(
        "SELECT usuario_id FROM pedidos WHERE id = %s", (pedido_id,), uno=True
    )
    if not pedido:
        return _error("El pedido no existe", 404)

    es_admin = g.usuario.get("rol") == "admin"
    if not es_admin and pedido["usuario_id"] != g.usuario["id"]:
        return _error("El pedido no existe", 404)

    comprobante = _consulta(
        "SELECT ruta_archivo FROM comprobantes_pago WHERE pedido_id = %s ORDER BY id DESC LIMIT 1",
        (pedido_id,), uno=True,
    )
    if not comprobante:
        return _error("Este pedido no tiene comprobante todavía", 404)

    # send_from_directory, y no abrir el archivo a mano, es lo que evita
    # que alguien, manipulando el nombre, pueda pedir un archivo fuera de
    # esta carpeta (path traversal): Flask valida la ruta por dentro.
    return send_from_directory(current_app.config["UPLOAD_FOLDER"], comprobante["ruta_archivo"])


@api_bp.put("/pedidos/<int:pedido_id>/pago")
@requiere_admin
def revisar_pago(pedido_id):
    """
    PUT /api/pedidos/<id>/pago
    Entrada: { "accion": "confirmar" } o { "accion": "rechazar" }
    Solo admin: después de mirar la imagen (GET .../comprobante), decide
    si el dinero sí llegó.

    - "confirmar" -> estado_pago pasa a 'confirmado' (la "compra
      completada" que pedía la guía del proyecto).
    - "rechazar"  -> estado_pago vuelve a 'rechazado'; el cliente puede
      subir un comprobante nuevo (subir_comprobante lo vuelve a poner en
      'en_revision' sin problema, sin importar el estado anterior).
    """
    datos = request.get_json(silent=True) or {}
    accion = str(datos.get("accion", "")).strip().lower()

    if accion not in ("confirmar", "rechazar"):
        return _error("Acción inválida: usa 'confirmar' o 'rechazar'")

    # La revisión debe ser atómica: solo se puede decidir un pago que esté
    # actualmente en revisión y tenga comprobante. Esto evita que dos
    # solicitudes simultáneas, o una repetición del mismo botón, confirmen
    # dos veces el mismo pedido y generen correos/PDF duplicados.
    nuevo_estado = "confirmado" if accion == "confirmar" else "rechazado"
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, estado_pago FROM pedidos WHERE id = %s FOR UPDATE",
            (pedido_id,),
        )
        pedido_actual = cursor.fetchone()
        if not pedido_actual:
            conn.rollback()
            return _error("El pedido no existe", 404)
        if pedido_actual["estado_pago"] != "en_revision":
            conn.rollback()
            return _error(
                f"El pago no está en revisión; estado actual: {pedido_actual['estado_pago']}",
                409,
            )

        cursor.execute(
            "SELECT id FROM comprobantes_pago WHERE pedido_id = %s ORDER BY id DESC LIMIT 1",
            (pedido_id,),
        )
        comprobante = cursor.fetchone()
        if not comprobante:
            conn.rollback()
            return _error("El pedido no tiene comprobante para revisar", 400)

        cursor.execute(
            "UPDATE pedidos SET estado_pago = %s WHERE id = %s",
            (nuevo_estado, pedido_id),
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()

    correo_enviado = False
    if nuevo_estado == "confirmado":
        try:
            from comprobante_pdf import generar_comprobante_pdf
            pedido = _consulta("""
                SELECT p.id, p.fecha, p.total, u.nombres, u.apellidos, u.correo, f.numero
                FROM pedidos p
                JOIN usuarios u ON u.id = p.usuario_id
                LEFT JOIN facturas f ON f.pedido_id = p.id
                WHERE p.id = %s
            """, (pedido_id,), uno=True)
            detalles = _consulta("""
                SELECT dp.cantidad, dp.precio_unitario, dp.subtotal, pr.nombre
                FROM detalle_pedido dp JOIN productos pr ON pr.id = dp.producto_id
                WHERE dp.pedido_id = %s ORDER BY dp.id
            """, (pedido_id,))
            pdf = generar_comprobante_pdf(pedido, detalles)
            _enviar_correo(
                pedido["correo"],
                f"Comprobante de compra {pedido['numero'] or pedido_id} - Florícola Los Álamos",
                "Hola,\n\nTu pago fue confirmado. Adjuntamos tu comprobante de compra en PDF.\n\nGracias por tu compra.",
                adjunto=pdf,
                nombre_adjunto=f"comprobante_{pedido_id}.pdf",
            )
            correo_enviado = True
        except Exception:
            current_app.logger.exception("Pago confirmado, pero no se pudo generar/enviar el comprobante")

    return jsonify({"id": pedido_id, "estado_pago": nuevo_estado, "correo_enviado": correo_enviado})


@api_bp.get("/clientes")
@requiere_admin
def listar_clientes():
    """
    GET /api/clientes?pagina=1&por_pagina=10&buscar=ana
    Solo admin. Devuelve los usuarios registrados (sin contraseñas,
    gracias a _usuario_publico), paginados y con búsqueda opcional por
    nombre, apellido o correo, por la misma razón que en /api/productos:
    no traer de golpe una tabla que puede crecer mucho.
    """
    _, por_pagina, offset = _paginacion()
    buscar = (request.args.get("buscar") or "").strip()

    condicion = ""
    parametros = ()
    if buscar:
        condicion = "WHERE nombres LIKE %s OR apellidos LIKE %s OR correo LIKE %s"
        comodin = f"%{buscar}%"
        parametros = (comodin, comodin, comodin)

    filas = _consulta(
        f"SELECT * FROM usuarios {condicion} ORDER BY nombres LIMIT %s OFFSET %s",
        parametros + (por_pagina, offset),
    )
    total = _consulta(
        f"SELECT COUNT(*) AS total FROM usuarios {condicion}", parametros, uno=True
    )["total"]

    return jsonify({
        "datos": [_usuario_publico(u) for u in filas],
        "total": total,
        "por_pagina": por_pagina,
    })
