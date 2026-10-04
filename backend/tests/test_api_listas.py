from datetime import datetime
from io import BytesIO

from flask import Flask

import api


def _crear_app(upload_folder=None):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = "test-secret"
    if upload_folder is not None:
        app.config["UPLOAD_FOLDER_BASE"] = str(upload_folder)
    app.register_blueprint(api.api_bp)
    return app


def _token(app, correo):
    with app.app_context():
        return api._serializer().dumps({"correo": correo})


def test_listas_estan_registradas_y_exigen_sesion():
    app = _crear_app()
    client = app.test_client()

    clientes = client.get("/api/clientes")
    pedidos = client.get("/api/pedidos")

    assert clientes.status_code == 401
    assert pedidos.status_code == 401


def test_status_responde_sin_conectarse_a_mysql():
    app = _crear_app()

    respuesta = app.test_client().get("/api/status")

    assert respuesta.status_code == 200
    assert respuesta.get_json() == {"status": "ok"}


def test_clientes_paginados_solo_para_admin(monkeypatch):
    usuario = {
        "id": 1,
        "correo": "admin@example.com",
        "rol": "admin",
    }
    consultas = []

    def consulta(sql, params=(), uno=False):
        consultas.append((sql, params, uno))
        if "SELECT * FROM usuarios WHERE correo = %s" in sql:
            return usuario
        if "COUNT(*)" in sql:
            return {"total": 1}
        return [{
            "id": 2,
            "usuario": "ana",
            "nombres": "Ana",
            "apellidos": "Pérez",
            "correo": "ana@example.com",
            "rol": "cliente",
            "edad": 30,
        }]

    monkeypatch.setattr(api, "_consulta", consulta)
    app = _crear_app()
    response = app.test_client().get(
        "/api/clientes?pagina=2&por_pagina=10&buscar=ana",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
    )

    assert response.status_code == 200
    assert response.get_json()["total"] == 1
    assert response.get_json()["datos"][0]["correo"] == "ana@example.com"
    assert consultas[-2][1] == ("%ana%", "%ana%", "%ana%", 10, 10)


def test_clientes_rechaza_usuario_no_administrador(monkeypatch):
    usuario = {"id": 2, "correo": "cliente@example.com", "rol": "cliente"}
    monkeypatch.setattr(api, "_consulta", lambda *args, **kwargs: usuario)
    app = _crear_app()

    response = app.test_client().get(
        "/api/clientes",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
    )

    assert response.status_code == 403


def test_pedidos_filtra_por_cliente_y_devuelve_fecha_iso(monkeypatch):
    usuario = {"id": 2, "correo": "ana@example.com", "rol": "cliente"}
    consultas = []

    def consulta(sql, params=(), uno=False):
        consultas.append((sql, params, uno))
        if "SELECT * FROM usuarios WHERE correo = %s" in sql:
            return usuario
        if "COUNT(*)" in sql:
            return {"total": 1}
        return [{
            "id": 15,
            "fecha": datetime(2026, 10, 3, 13, 49, 35),
            "estado": "pendiente",
            "estado_pago": "pendiente",
            "total": 12.5,
            "nombres": "Ana",
            "apellidos": "Pérez",
        }]

    monkeypatch.setattr(api, "_consulta", consulta)
    app = _crear_app()
    response = app.test_client().get(
        "/api/pedidos?pagina=1&por_pagina=50",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
    )

    assert response.status_code == 200
    pedido = response.get_json()["datos"][0]
    assert pedido["fecha"] == "2026-10-03T13:49:35"
    assert pedido["total"] == 12.5
    assert consultas[1][1] == (usuario["id"], 50, 0)


def test_eliminar_pedido_cancelado_solo_permite_admin_y_estado_cancelado(
    tmp_path, monkeypatch
):
    admin = {"id": 1, "correo": "admin@example.com", "rol": "admin"}
    cliente = {"id": 2, "correo": "ana@example.com", "rol": "cliente"}
    estado_pedido = "cancelado"
    comprobante = "15_prueba.png"
    ruta_comprobante = tmp_path / comprobante
    ruta_comprobante.write_bytes(b"imagen")
    operaciones = []

    class CursorSimulado:
        rowcount = 1

        def execute(self, sql, params=()):
            operaciones.append((sql, params))

        def fetchone(self):
            return {"estado": estado_pedido}

        def fetchall(self):
            return [{"ruta_archivo": comprobante}]

        def close(self):
            pass

    class ConexionSimulada:
        def cursor(self, dictionary=False):
            assert dictionary
            return CursorSimulado()

        def commit(self):
            operaciones.append(("COMMIT", ()))

        def rollback(self):
            operaciones.append(("ROLLBACK", ()))

        def close(self):
            pass

    monkeypatch.setattr(api, "_consulta", lambda *args, **kwargs: admin)
    monkeypatch.setattr(api, "get_connection", ConexionSimulada)
    app = _crear_app(tmp_path)
    app.config["UPLOAD_FOLDER"] = str(tmp_path)
    client = app.test_client()

    def headers(correo):
        return {"Authorization": f"Bearer {_token(app, correo)}"}

    monkeypatch.setattr(
        api,
        "_consulta",
        lambda *args, **kwargs: (
            admin if kwargs.get("uno") and args[1] == (admin["correo"],) else cliente
        ),
    )
    no_admin = client.delete("/api/pedidos/15", headers=headers(cliente["correo"]))
    assert no_admin.status_code == 403
    assert not operaciones

    monkeypatch.setattr(api, "_consulta", lambda *args, **kwargs: admin)
    estado_pedido = "pendiente"
    no_cancelado = client.delete(
        "/api/pedidos/15",
        headers=headers(admin["correo"]),
    )
    assert no_cancelado.status_code == 409
    assert operaciones[-1] == ("ROLLBACK", ())
    assert ruta_comprobante.exists()

    estado_pedido = "cancelado"
    response = client.delete("/api/pedidos/15", headers=headers(admin["correo"]))

    assert response.status_code == 200
    assert response.get_json()["mensaje"] == "Pedido cancelado eliminado"
    assert not ruta_comprobante.exists()
    assert operaciones[-1] == ("COMMIT", ())
    assert "DELETE FROM pedidos" in operaciones[-2][0]


def test_crear_pedido_devuelve_fecha_iso_para_flutter(monkeypatch):
    usuario = {
        "id": 3,
        "correo": "ana@example.com",
        "rol": "cliente",
    }
    fecha = datetime(2026, 10, 3, 16, 58, 42)

    class CursorSimulado:
        lastrowid = 31

        def __init__(self):
            self.resultado = None

        def execute(self, sql, params=()):
            if "SELECT id, nombre, cantidad, precio FROM productos" in sql:
                self.resultado = {
                    "id": 7,
                    "nombre": "Girasol",
                    "cantidad": 12,
                    "precio": 0.9,
                }
            elif "INSERT INTO pedidos" in sql:
                self.lastrowid = 31

        def fetchone(self):
            return self.resultado

    class ConexionSimulada:
        def cursor(self, dictionary=False):
            assert dictionary
            return CursorSimulado()

        def commit(self):
            pass

        def rollback(self):
            pass

        def close(self):
            pass

    def consulta(sql, params=(), uno=False):
        if "SELECT * FROM usuarios WHERE correo = %s" in sql:
            return usuario
        if "SELECT fecha FROM pedidos WHERE id = %s" in sql:
            return {"fecha": fecha}
        raise AssertionError(f"Consulta inesperada: {sql}")

    api._RATE_LIMIT.clear()
    monkeypatch.setattr(api, "_consulta", consulta)
    monkeypatch.setattr(api, "get_connection", ConexionSimulada)
    app = _crear_app()
    response = app.test_client().post(
        "/api/pedidos",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
        json={"items": [{"producto_id": 7, "cantidad": 2}]},
    )

    assert response.status_code == 201
    assert response.get_json()["fecha"] == "2026-10-03T16:58:42"


def test_admin_puede_cambiar_fondo_y_gestionar_galeria(tmp_path, monkeypatch):
    usuario = {"id": 1, "correo": "admin@example.com", "rol": "admin"}
    monkeypatch.setattr(api, "_consulta", lambda *args, **kwargs: usuario)
    app = _crear_app(tmp_path)
    client = app.test_client()
    headers = {
        "Authorization": f"Bearer {_token(app, usuario['correo'])}",
    }

    background = client.post(
        "/api/inicio/fondo",
        headers=headers,
        data={"imagen": (BytesIO(b"background"), "garden.png")},
        content_type="multipart/form-data",
    )
    assert background.status_code == 200
    fondo = background.get_json()["fondo"]

    gallery = client.post(
        "/api/inicio/galeria",
        headers=headers,
        data={"imagen": (BytesIO(b"gallery"), "flowers.jpg")},
        content_type="multipart/form-data",
    )
    assert gallery.status_code == 201
    imagen = gallery.get_json()["galeria"][0]

    contenido = client.get("/api/inicio/contenido", headers=headers)
    assert contenido.get_json() == {"fondo": fondo, "galeria": [imagen]}
    assert client.get(f"/api/inicio/imagenes/{fondo}").data == b"background"
    assert client.get(f"/api/inicio/imagenes/{imagen}").data == b"gallery"

    quitar_imagen = client.delete(
        f"/api/inicio/galeria/{imagen}",
        headers=headers,
    )
    quitar_fondo = client.delete("/api/inicio/fondo", headers=headers)
    assert quitar_imagen.status_code == 200
    assert quitar_fondo.status_code == 200
    assert client.get("/api/inicio/contenido", headers=headers).get_json() == {
        "fondo": None,
        "galeria": [],
    }


def test_usuario_actualiza_su_perfil_y_solicita_verificacion_de_correo(monkeypatch):
    usuario = {
        "id": 7,
        "usuario": "ana",
        "nombres": "Ana",
        "apellidos": "Pérez",
        "correo": "ana@example.com",
        "edad": 30,
        "rol": "cliente",
        "email_verificado": True,
    }
    consultas = []
    verificaciones = []

    def consulta(sql, params=(), uno=False):
        consultas.append((sql, params, uno))
        if "AND id <> %s" in sql:
            return None
        if "WHERE correo = %s" in sql:
            return usuario
        if "WHERE id = %s" in sql:
            return usuario
        raise AssertionError(f"Consulta inesperada: {sql}")

    monkeypatch.setattr(api, "_consulta", consulta)
    monkeypatch.setattr(api, "_ejecutar", lambda *args: (1, None))
    monkeypatch.setattr(
        api,
        "_crear_verificacion",
        lambda *args: verificaciones.append(args),
    )
    app = _crear_app()
    response = app.test_client().put(
        "/api/me",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
        json={
            "usuario": "ana-rios",
            "nombres": "Ana María",
            "apellidos": "Pérez",
            "correo": "ana.nueva@example.com",
            "edad": 31,
        },
    )

    assert response.status_code == 200
    assert response.get_json()["correo_pendiente"] == "ana.nueva@example.com"
    assert verificaciones == [
        (usuario["id"], "ana@example.com", "ana.nueva@example.com")
    ]


def test_verificar_correo_nuevo_renueva_token_solo_al_usuario(monkeypatch):
    usuario = {
        "id": 7,
        "usuario": "ana",
        "nombres": "Ana",
        "apellidos": "Pérez",
        "correo": "ana@example.com",
        "edad": 30,
        "rol": "cliente",
        "email_verificado": True,
    }
    consultas = []
    usuario_lookup = 0

    def consulta(sql, params=(), uno=False):
        nonlocal usuario_lookup
        consultas.append((sql, params, uno))
        if "FROM verificaciones_email" in sql:
            return {
                "id": 15,
                "usuario_id": usuario["id"],
                "correo_destino": "ana.nueva@example.com",
            }
        if "SELECT id FROM usuarios WHERE correo = %s" in sql:
            return None
        if "WHERE id = %s" in sql:
            usuario_lookup += 1
            if usuario_lookup == 1:
                return usuario
            return {**usuario, "correo": "ana.nueva@example.com"}
        raise AssertionError(f"Consulta inesperada: {sql}")

    monkeypatch.setattr(api, "_consulta", consulta)
    monkeypatch.setattr(api, "_ejecutar", lambda *args: (1, None))
    app = _crear_app()
    response = app.test_client().post(
        "/api/verificar-email",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
        json={"correo": "ana.nueva@example.com", "codigo": "123456"},
    )

    assert response.status_code == 200
    assert response.get_json()["usuario"]["correo"] == "ana.nueva@example.com"
    assert isinstance(response.get_json()["token"], str)


def test_admin_edita_usuario_y_cliente_no_puede_usar_ruta_admin(monkeypatch):
    usuario = {"id": 1, "correo": "ana@example.com", "rol": "cliente"}
    monkeypatch.setattr(api, "_consulta", lambda *args, **kwargs: usuario)
    app = _crear_app()
    response = app.test_client().put(
        "/api/clientes/8",
        headers={"Authorization": f"Bearer {_token(app, usuario['correo'])}"},
        json={
            "usuario": "cliente",
            "nombres": "Cliente",
            "apellidos": "Ejemplo",
            "correo": "cliente@example.com",
            "edad": 25,
        },
    )
    assert response.status_code == 403


def test_admin_puede_editar_datos_personales_de_usuario(monkeypatch):
    admin = {"id": 1, "correo": "admin@example.com", "rol": "admin"}
    cliente = {
        "id": 8,
        "usuario": "cliente",
        "nombres": "Cliente",
        "apellidos": "Actualizado",
        "correo": "cliente@example.com",
        "edad": 25,
        "rol": "cliente",
        "email_verificado": True,
    }

    def consulta(sql, params=(), uno=False):
        if "WHERE correo = %s" in sql:
            return admin
        if "AND id <> %s" in sql:
            return None
        if "WHERE id = %s" in sql:
            return cliente
        raise AssertionError(f"Consulta inesperada: {sql}")

    monkeypatch.setattr(api, "_consulta", consulta)
    monkeypatch.setattr(api, "_ejecutar", lambda *args: (1, None))
    app = _crear_app()
    response = app.test_client().put(
        "/api/clientes/8",
        headers={"Authorization": f"Bearer {_token(app, admin['correo'])}"},
        json={
            "usuario": "cliente",
            "nombres": "Cliente",
            "apellidos": "Actualizado",
            "correo": "cliente@example.com",
            "edad": 26,
        },
    )

    assert response.status_code == 200
    assert response.get_json()["usuario"]["rol"] == "cliente"


def test_recuperacion_responde_igual_para_correos_existentes_y_desconocidos(
    monkeypatch,
):
    api._RATE_LIMIT.clear()
    guardados = []
    enviados = []

    def consulta(sql, params=(), uno=False):
        return {"id": 4} if params == ("ana@example.com",) else None

    monkeypatch.setattr(api, "_consulta", consulta)
    monkeypatch.setattr(api, "_ejecutar", lambda sql, params: guardados.append(params))
    monkeypatch.setattr(api, "_codigo_verificacion", lambda: "123456")
    monkeypatch.setattr(
        api,
        "_enviar_correo",
        lambda correo, asunto, cuerpo: enviados.append((correo, cuerpo)),
    )

    app = _crear_app()
    client = app.test_client()
    desconocido = client.post(
        "/api/password/recuperar",
        json={"correo": "nadie@example.com"},
    )
    existente = client.post(
        "/api/password/recuperar",
        json={"correo": "ana@example.com"},
    )

    assert desconocido.status_code == existente.status_code == 200
    assert desconocido.get_json() == existente.get_json()
    with app.app_context():
        hash_codigo = api._hash_codigo_recuperacion("123456")
    assert guardados[0][1] == hash_codigo
    assert guardados[0][1] != "123456"
    assert enviados[0][0] == "ana@example.com"
    assert "123456" in enviados[0][1]


def test_restaurar_password_consume_codigo_atomico_y_solo_una_vez(monkeypatch):
    class CursorSimulado:
        def __init__(self, conn):
            self.conn = conn
            self.resultado = None

        def execute(self, sql, params):
            if "SELECT id" in sql and "FROM usuarios" in sql:
                self.resultado = {"id": 4}
            elif "SELECT codigo_hash" in sql:
                self.resultado = self.conn.codigo
            elif "UPDATE usuarios SET password" in sql:
                self.conn.password_guardada = params[0]
            elif "UPDATE codigos_recuperacion" in sql and "SET usado" in sql:
                self.conn.codigo["usado"] = True
            elif "SET intentos = intentos + 1" in sql:
                self.conn.codigo["intentos"] += 1
            else:
                raise AssertionError(f"Consulta inesperada: {sql}")

        def fetchone(self):
            return self.resultado

    class ConexionSimulada:
        def __init__(self, hash_codigo):
            self.codigo = {
                "codigo_hash": hash_codigo,
                "intentos": 0,
                "usado": False,
                "vigente": 1,
            }
            self.password_guardada = None
            self.commit_count = 0

        def cursor(self, dictionary=False):
            assert dictionary
            return CursorSimulado(self)

        def commit(self):
            self.commit_count += 1

        def rollback(self):
            pass

        def close(self):
            pass

    app = _crear_app()
    with app.app_context():
        conexion = ConexionSimulada(api._hash_codigo_recuperacion("123456"))
        monkeypatch.setattr(api, "get_connection", lambda: conexion)
        monkeypatch.setattr(api, "hash_password", lambda password: f"hash:{password}")

        assert api._restablecer_password(
            "ana@example.com",
            "123456",
            "NuevaClave1!",
        )
        assert not api._restablecer_password(
            "ana@example.com",
            "123456",
            "OtraClave2!",
        )
    assert conexion.commit_count == 1
    assert conexion.password_guardada == "hash:NuevaClave1!"
    assert conexion.codigo["usado"]


def test_endpoint_restaurar_password_valida_clave_y_codigo(monkeypatch):
    llamadas = []
    monkeypatch.setattr(
        api,
        "_restablecer_password",
        lambda correo, codigo, password: llamadas.append(
            (correo, codigo, password)
        ) or True,
    )
    api._RATE_LIMIT.clear()
    client = _crear_app().test_client()

    invalida = client.post(
        "/api/password/restablecer",
        json={
            "correo": "ana@example.com",
            "codigo": "12345",
            "nueva_password": "NuevaClave1!",
        },
    )
    assert invalida.status_code == 400
    assert llamadas == []

    correcta = client.post(
        "/api/password/restablecer",
        json={
            "correo": "ana@example.com",
            "codigo": "123456",
            "nueva_password": "NuevaClave1!",
        },
    )
    assert correcta.status_code == 200
    assert llamadas == [("ana@example.com", "123456", "NuevaClave1!")]


def test_smtp_quita_espacios_de_contrasena_de_aplicacion(monkeypatch):
    credenciales = {}

    class SmtpSimulado:
        def __init__(self, host, port, timeout):
            assert host == "smtp.gmail.com"
            assert port == 587

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def starttls(self):
            pass

        def login(self, usuario, password):
            credenciales.update(usuario=usuario, password=password)

        def send_message(self, mensaje):
            assert mensaje["To"] == "ana@example.com"

    monkeypatch.setenv("SMTP_HOST", "smtp.gmail.com")
    monkeypatch.setenv("SMTP_PORT", "587")
    monkeypatch.setenv("SMTP_USER", "floricola@gmail.com")
    monkeypatch.setenv("SMTP_PASSWORD", "abcd efgh ijkl mnop")
    monkeypatch.setenv("SMTP_FROM", "floricola@gmail.com")
    monkeypatch.setenv("SMTP_STARTTLS", "1")
    monkeypatch.setattr(api.smtplib, "SMTP", SmtpSimulado)

    api._enviar_correo("ana@example.com", "Prueba", "Mensaje de prueba")

    assert credenciales == {
        "usuario": "floricola@gmail.com",
        "password": "abcdefghijklmnop",
    }
