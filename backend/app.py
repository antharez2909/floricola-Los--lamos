import os
import re
from html import escape

from flask import Flask, render_template, request, redirect, session
from flask_cors import CORS

from api import (
    api_bp,
    _password_valida,
    _crear_verificacion,
    _consulta,
    _ejecutar,
    _limitar_intentos,
)
from database import get_connection
from seguridad import hash_password, verificar_password


# ==================================================
# CONFIGURACIÓN DE FLASK
# ==================================================

app = Flask(__name__)

app.secret_key = os.environ.get("SECRET_KEY") or os.urandom(24)


# ==================================================
# CONFIGURACIÓN CORS
# Permite que Flutter Web pueda comunicarse
# con la API Flask desde Chrome o Edge.
# ==================================================

CORS(
    app,
    resources={
        r"/api/*": {
            "origins": "*",
        }
    },
    supports_credentials=False,
)


# ==================================================
# CONFIGURACIÓN DE ARCHIVOS
# ==================================================

app.config["UPLOAD_FOLDER_BASE"] = os.path.join(
    os.path.dirname(__file__),
    "uploads",
)

app.config["UPLOAD_FOLDER"] = os.path.join(
    app.config["UPLOAD_FOLDER_BASE"],
    "comprobantes",
)

os.makedirs(
    app.config["UPLOAD_FOLDER"],
    exist_ok=True,
)

os.makedirs(
    os.path.join(
        app.config["UPLOAD_FOLDER_BASE"],
        "productos",
    ),
    exist_ok=True,
)

os.makedirs(
    os.path.join(
        app.config["UPLOAD_FOLDER_BASE"],
        "inicio",
    ),
    exist_ok=True,
)


# ==================================================
# LÍMITE MÁXIMO DE ARCHIVOS
# 5 MB
# ==================================================

app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024


# ==================================================
# REGISTRO DE LA API
# ==================================================

app.register_blueprint(api_bp)


# ==================================================
# FUNCIONES AUXILIARES
# ==================================================

def usuario_logueado():
    """
    Devuelve True si existe una sesión de navegador
    con usuario y correo.
    """
    return (
        "usuario" in session
        and "correo" in session
    )


def es_admin():
    """
    Devuelve True si el usuario de la sesión actual
    tiene el rol de administrador.
    """
    return session.get("rol") == "admin"


def obtener_usuario_por_correo(correo):
    """
    Busca un usuario por su correo electrónico.
    """
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(dictionary=True)

        sql = """
            SELECT *
            FROM usuarios
            WHERE correo = %s
        """

        cursor.execute(sql, (correo,))
        usuario = cursor.fetchone()

        return usuario

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ==================================================
# RUTAS WEB
# ==================================================

@app.route("/")
def index():
    """
    Página principal de la versión web.
    """
    if not usuario_logueado():
        return redirect("/login")

    return render_template("index.html")


@app.route("/about")
def about():
    """
    Página informativa.
    """
    if not usuario_logueado():
        return redirect("/login")

    return render_template("about.html")


# ==================================================
# LOGIN WEB
# ==================================================

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None

    if request.method == "POST":

        limitado = _limitar_intentos(
            "web-login",
            10,
            60,
        )

        if limitado:
            return limitado

        correo = (
            request.form
            .get("correo", "")
            .strip()
            .lower()
        )

        password = request.form.get(
            "password",
            "",
        )

        usuario = obtener_usuario_por_correo(correo)

        if usuario:

            ok, actualizar = verificar_password(
                usuario["password"],
                password,
            )

            if ok:

                # Actualiza el hash si seguridad.py
                # indica que es necesario.
                if actualizar:
                    conn = None
                    cursor = None

                    try:
                        conn = get_connection()
                        cursor = conn.cursor()

                        cursor.execute(
                            """
                            UPDATE usuarios
                            SET password = %s
                            WHERE correo = %s
                            """,
                            (
                                hash_password(password),
                                usuario["correo"],
                            ),
                        )

                        conn.commit()

                    except Exception:
                        if conn:
                            conn.rollback()

                        app.logger.exception(
                            "No se pudo actualizar el hash"
                        )

                    finally:
                        if cursor:
                            cursor.close()

                        if conn:
                            conn.close()

                # Verificación del correo.
                if not usuario.get(
                    "email_verificado",
                    True,
                ):
                    error = (
                        "Debes verificar tu correo "
                        "electrónico antes de iniciar sesión"
                    )

                else:
                    session["usuario"] = usuario["usuario"]
                    session["correo"] = usuario["correo"]
                    session["rol"] = usuario["rol"]

                    return redirect("/")

            else:
                error = "Credenciales incorrectas"

        else:
            error = "Credenciales incorrectas"

    return render_template(
        "login.html",
        error=error,
    )


# ==================================================
# REGISTRO WEB
# ==================================================

@app.route("/registro", methods=["GET", "POST"])
def registro():
    error = None

    if request.method == "POST":

        limitado = _limitar_intentos(
            "web-registro",
            5,
            600,
        )

        if limitado:
            return limitado

        nombres = (
            request.form
            .get("nombres", "")
            .strip()
        )

        apellidos = (
            request.form
            .get("apellidos", "")
            .strip()
        )

        correo = (
            request.form
            .get("correo", "")
            .strip()
            .lower()
        )

        password = request.form.get(
            "password",
            "",
        )

        try:
            edad = int(
                request.form.get(
                    "edad",
                    "",
                )
            )
        except (ValueError, TypeError):
            edad = None

        # ------------------------------------------
        # VALIDACIONES
        # ------------------------------------------

        if not nombres or not apellidos:

            error = (
                "Ingresa tus nombres y apellidos"
            )

        elif (
            "@" not in correo
            or "." not in correo.split("@")[-1]
        ):

            error = "El correo no es válido"

        elif not _password_valida(password):

            error = (
                "La contraseña debe tener entre "
                "8 y 64 caracteres, una mayúscula, "
                "un número y un signo especial"
            )

        elif edad is None or not 1 <= edad <= 120:

            error = (
                "La edad debe estar entre 1 y 120"
            )

        elif _consulta(
            """
            SELECT id
            FROM usuarios
            WHERE correo = %s
            """,
            (correo,),
            uno=True,
        ):

            error = "Usuario ya registrado"

        else:

            # --------------------------------------
            # CREAR USUARIO
            # --------------------------------------

            _, nuevo_id = _ejecutar(
                """
                INSERT INTO usuarios
                (
                    usuario,
                    nombres,
                    apellidos,
                    correo,
                    edad,
                    password,
                    rol,
                    email_verificado
                )
                VALUES
                (
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    'cliente',
                    FALSE
                )
                """,
                (
                    correo,
                    nombres,
                    apellidos,
                    correo,
                    edad,
                    hash_password(password),
                ),
            )

            # --------------------------------------
            # CREAR VERIFICACIÓN
            # --------------------------------------

            try:

                _crear_verificacion(
                    nuevo_id,
                    correo,
                )

            except Exception:

                try:
                    _ejecutar(
                        """
                        DELETE FROM usuarios
                        WHERE id = %s
                        """,
                        (nuevo_id,),
                    )
                except Exception:
                    app.logger.exception(
                        "No se pudo eliminar el usuario"
                    )

                app.logger.exception(
                    "No se pudo enviar el correo "
                    "de verificación web"
                )

                error = (
                    "No se pudo enviar el correo "
                    "de verificación. Revisa la "
                    "configuración SMTP del servidor."
                )

            else:

                return redirect(
                    "/verificar-email-web"
                    f"?correo={correo}"
                )

    return render_template(
        "registro.html",
        error=error,
    )


# ==================================================
# VERIFICACIÓN DE CORREO WEB
# ==================================================

@app.route(
    "/verificar-email-web",
    methods=["GET", "POST"],
)
def verificar_email_web():

    if request.method == "GET":

        correo = (
            request.args
            .get("correo", "")
            .strip()
            .lower()
        )

    else:

        correo = (
            request.form
            .get("correo", "")
            .strip()
            .lower()
        )

    error = None
    mensaje = None

    # ----------------------------------------------
    # PROCESAR CÓDIGO
    # ----------------------------------------------

    if request.method == "POST":

        codigo = (
            request.form
            .get("codigo", "")
            .strip()
        )

        if not re.fullmatch(
            r"\d{6}",
            codigo,
        ):

            error = (
                "El código debe tener 6 dígitos"
            )

        else:

            usuario = _consulta(
                """
                SELECT id, email_verificado
                FROM usuarios
                WHERE correo = %s
                """,
                (correo,),
                uno=True,
            )

            if not usuario:

                error = (
                    "No existe una cuenta "
                    "con ese correo"
                )

            elif usuario["email_verificado"]:

                mensaje = (
                    "El correo ya estaba verificado. "
                    "Ya puedes iniciar sesión."
                )

            else:

                ver = _consulta(
                    """
                    SELECT id
                    FROM verificaciones_email
                    WHERE usuario_id = %s
                      AND codigo = %s
                      AND usado = FALSE
                      AND expiracion > NOW()
                    ORDER BY id DESC
                    LIMIT 1
                    """,
                    (
                        usuario["id"],
                        codigo,
                    ),
                    uno=True,
                )

                if not ver:

                    error = (
                        "Código incorrecto o vencido"
                    )

                else:

                    _ejecutar(
                        """
                        UPDATE usuarios
                        SET email_verificado = TRUE
                        WHERE id = %s
                        """,
                        (usuario["id"],),
                    )

                    _ejecutar(
                        """
                        UPDATE verificaciones_email
                        SET usado = TRUE
                        WHERE id = %s
                        """,
                        (ver["id"],),
                    )

                    mensaje = (
                        "Correo verificado correctamente. "
                        "Ya puedes iniciar sesión."
                    )

    # ----------------------------------------------
    # ESCAPAR CORREO PARA HTML
    # ----------------------------------------------

    correo_html = escape(
        correo,
        quote=True,
    )

    error_html = (
        f"<p style='color:red'>{escape(error)}</p>"
        if error
        else ""
    )

    mensaje_html = (
        f"<p style='color:green'>{escape(mensaje)}</p>"
        if mensaje
        else ""
    )

    # ----------------------------------------------
    # HTML DE VERIFICACIÓN
    # ----------------------------------------------

    html = f"""
<!doctype html>
<html lang="es">

<head>

    <meta charset="utf-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1"
    >

    <title>Verificar correo</title>

</head>

<body
    style="
        font-family: Arial, sans-serif;
        max-width: 520px;
        margin: 40px auto;
        padding: 20px;
    "
>

    <h1>Verificar correo</h1>

    <p>
        Escribe el código de 6 dígitos enviado a
        <b>{correo_html}</b>.
    </p>

    <form method="post">

        <input
            type="hidden"
            name="correo"
            value="{correo_html}"
        >

        <input
            name="codigo"
            inputmode="numeric"
            maxlength="6"
            pattern="[0-9]{{6}}"
            placeholder="Código de 6 dígitos"
            required
        >

        <button type="submit">
            Verificar
        </button>

    </form>

    {error_html}

    {mensaje_html}

</body>

</html>
"""

    return html


# ==================================================
# LOGOUT
# ==================================================

@app.route("/logout")
def logout():

    session.clear()

    return redirect("/login")


# ==================================================
# CLIENTES
# ==================================================

@app.route("/clientes")
def clientes():

    if not usuario_logueado():
        return redirect("/login")

    # ----------------------------------------------
    # ADMIN
    # ----------------------------------------------

    if es_admin():

        conn = None
        cursor = None

        try:

            conn = get_connection()
            cursor = conn.cursor(
                dictionary=True
            )

            cursor.execute(
                "SELECT * FROM usuarios"
            )

            usuarios = cursor.fetchall()

        finally:

            if cursor:
                cursor.close()

            if conn:
                conn.close()

        return render_template(
            "clientes_admin.html",
            usuarios=usuarios,
        )

    # ----------------------------------------------
    # CLIENTE
    # ----------------------------------------------

    correo = session["correo"]

    cliente = obtener_usuario_por_correo(
        correo
    )

    if not cliente:

        session.clear()

        return redirect("/login")

    return render_template(
        "clientes.html",
        cliente=cliente,
    )


# ==================================================
# INVENTARIO
# ==================================================

@app.route("/inventario")
def inventario():

    if not usuario_logueado():
        return redirect("/login")

    conn = None
    cursor = None

    try:

        conn = get_connection()
        cursor = conn.cursor(
            dictionary=True
        )

        cursor.execute(
            "SELECT * FROM productos"
        )

        productos = cursor.fetchall()

    finally:

        if cursor:
            cursor.close()

        if conn:
            conn.close()

    return render_template(
        "inventario.html",
        productos=productos,
    )


# ==================================================
# AGREGAR PRODUCTO
# ==================================================

@app.route(
    "/agregar_producto",
    methods=["POST"],
)
def agregar_producto():

    if not usuario_logueado():
        return redirect("/login")

    if not es_admin():
        return redirect("/inventario")

    nombre = (
        request.form
        .get("nombre", "")
        .strip()
    )

    cantidad = request.form.get(
        "cantidad",
        0,
    )

    precio = request.form.get(
        "precio",
        0.0,
    )

    if not nombre:
        return redirect("/inventario")

    conn = None
    cursor = None

    try:

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            INSERT INTO productos
            (
                nombre,
                cantidad,
                precio
            )
            VALUES
            (
                %s,
                %s,
                %s
            )
            """,
            (
                nombre,
                cantidad,
                precio,
            ),
        )

        conn.commit()

    except Exception:

        if conn:
            conn.rollback()

        app.logger.exception(
            "Error al agregar producto"
        )

    finally:

        if cursor:
            cursor.close()

        if conn:
            conn.close()

    return redirect("/inventario")


# ==================================================
# ELIMINAR PRODUCTO
# ==================================================

@app.route(
    "/eliminar_producto/<int:id>"
)
def eliminar_producto(id):

    if not usuario_logueado():
        return redirect("/login")

    if not es_admin():
        return redirect("/inventario")

    conn = None
    cursor = None

    try:

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            DELETE FROM productos
            WHERE id = %s
            """,
            (id,),
        )

        conn.commit()

    except Exception:

        if conn:
            conn.rollback()

        app.logger.exception(
            "Error al eliminar producto"
        )

    finally:

        if cursor:
            cursor.close()

        if conn:
            conn.close()

    return redirect("/inventario")


# ==================================================
# IMPORTANTE:
# /api/status NO SE DEFINE AQUÍ
#
# Ya existe en api.py mediante:
# @api_bp.route("/api/status", methods=["GET"])
#
# Se evita así tener dos rutas iguales.
# ==================================================


# ==================================================
# EJECUCIÓN DEL SERVIDOR
# ==================================================

if __name__ == "__main__":

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=os.environ.get("FLASK_DEBUG") == "1",
    )