# ======================================================================
# SEGURIDAD: MANEJO DE CONTRASEÑAS
# ======================================================================
# Regla de oro de cualquier sistema con login: la contraseña del usuario
# NUNCA se guarda tal cual en la base de datos. Si alguien lograra leer
# la tabla 'usuarios' (por un descuido, una fuga, un backup mal guardado),
# no debería poder ver las contraseñas reales de nadie.
#
# La solución es el "hash": una función matemática que convierte
# "admin123" en algo como "scrypt:32768:8:1$abc123...$f9e8d7..." de forma
# que:
#   - Es prácticamente imposible reconstruir "admin123" a partir del hash.
#   - La MISMA contraseña siempre da el MISMO hash, así que para verificar
#     un login no hace falta "deshacer" el hash: solo hay que volver a
#     aplicar la función a la contraseña que el usuario escribió y
#     comparar el resultado con el hash guardado.
#
# Este proyecto usa 'scrypt', el algoritmo de hash que ya trae incluido
# Werkzeug (la librería sobre la que está construido Flask), así que no
# hace falta instalar nada aparte.

import hmac

from werkzeug.security import check_password_hash, generate_password_hash


def hash_password(password):
    """
    Convierte una contraseña en texto plano ("admin123") en un hash seguro
    para guardar en la base de datos.

    Se usa en dos momentos:
      - Al registrar una cuenta nueva (api.py: /api/registro).
      - Al migrar una cuenta vieja de texto plano a hash, la primera vez
        que esa cuenta inicia sesión con éxito (ver verificar_password).
    """
    return generate_password_hash(password)


def es_hash(valor):
    """
    Distingue si lo que hay guardado en la columna 'password' YA es un
    hash (cuentas creadas con este sistema) o todavía es texto plano
    (cuentas heredadas del proyecto original, antes de este cambio).

    Los hashes que genera Werkzeug siempre empiezan con el nombre del
    algoritmo seguido de ":", por ejemplo "scrypt:..." o, en versiones
    más viejas de Werkzeug, "pbkdf2:...". Una contraseña de verdad como
    "admin123" o "flor2024" nunca tendría esa forma, así que basta con
    revisar cómo empieza el texto para saber en qué caso se está.
    """
    return isinstance(valor, str) and valor.startswith(("scrypt:", "pbkdf2:"))


def verificar_password(guardado, ingresado):
    """
    Compara la contraseña que el usuario escribió al iniciar sesión
    ('ingresado') contra lo que hay guardado en la base de datos
    ('guardado'), sea que ese valor ya esté hasheado o no.

    Devuelve una tupla (es_correcta, debe_actualizarse_a_hash):
      - es_correcta:  True si la contraseña coincide.
      - debe_actualizarse_a_hash: True solo cuando la cuenta todavía
        estaba en texto plano Y la contraseña ingresada fue correcta.
        Quien llama a esta función (ver api.py y app.py) usa esta señal
        para, en ese preciso momento, sobrescribir la columna 'password'
        con hash_password(ingresado) y así "migrar" la cuenta sin que el
        usuario tenga que hacer nada especial: simplemente inicia sesión
        como siempre y su cuenta queda protegida desde ese login en adelante.

    Casos que cubre:
      1. guardado es None (el correo no existe) o ingresado viene vacío
         -> no hay nada que comparar, se responde que no coincide.
      2. guardado YA es un hash -> se usa check_password_hash, la función
         de Werkzeug hecha justo para esto: vuelve a aplicar el mismo
         algoritmo a 'ingresado' y compara los resultados.
      3. guardado es texto plano (cuenta vieja) -> se comparan los dos
         textos directamente, pero con hmac.compare_digest en vez de
         simplemente "if guardado == ingresado". compare_digest tarda
         siempre el mismo tiempo sin importar en qué posición difieren
         los textos, mientras que "==" normal es un poquito más rápido
         cuando falla antes: esa diferencia de tiempo, medida muchas
         veces, es un dato real que un atacante podría explotar para
         adivinar la contraseña letra por letra (esto se llama "timing
         attack"). En este caso, cuando devuelve True, también se marca
         que la cuenta debe convertirse a hash ya mismo.
    """
    if not guardado or ingresado is None:
        return False, False

    if es_hash(guardado):
        return check_password_hash(guardado, ingresado), False

    ok = hmac.compare_digest(str(guardado).encode("utf-8"), ingresado.encode("utf-8"))
    return ok, ok
