# ======================================================================
# SCRIPT: convertir TODAS las contraseñas viejas (texto plano) a hash
# ======================================================================
# Este archivo no forma parte del servidor: no tiene rutas, no se deja
# corriendo. Es un script que se ejecuta UNA vez, a mano, desde la
# terminal:
#
#       python migrar_passwords.py
#
# ¿Para qué sirve si api.py y app.py ya migran cada cuenta sola cuando
# esa cuenta inicia sesión (ver seguridad.py)? Para los casos en que no
# se quiere esperar a que cada cliente vuelva a entrar: por ejemplo,
# antes de una entrega o revisión del proyecto, para dejar toda la tabla
# 'usuarios' ya convertida a hash de una sola vez.
#
# Requisito antes de correrlo: haber ejecutado migracion.sql en MySQL,
# para que la columna 'password' sea lo bastante larga como para guardar
# un hash (~255 caracteres) y no un error de "dato demasiado largo".

from database import get_connection
from seguridad import es_hash, hash_password

# 1) Traer TODOS los usuarios de la base de datos.
conn = get_connection()
cursor = conn.cursor(dictionary=True)
cursor.execute("SELECT correo, password FROM usuarios")

# 2) Quedarse solo con los que todavía tienen la contraseña en texto
#    plano (es_hash devuelve False para esos). Los que ya están en hash
#    no se tocan: convertir un hash "otra vez" lo dejaría inservible,
#    porque ya no sería el hash de la contraseña original.
pendientes = [u for u in cursor.fetchall() if not es_hash(u["password"])]

# 3) Por cada cuenta pendiente, calcular su hash y actualizar la fila.
for u in pendientes:
    cursor.execute(
        "UPDATE usuarios SET password = %s WHERE correo = %s",
        (hash_password(u["password"]), u["correo"]),
    )

# 4) Confirmar todos los cambios de una vez y cerrar la conexión.
conn.commit()
conn.close()

print(f"Listo: {len(pendientes)} contraseña(s) convertidas a hash.")
