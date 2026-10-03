"""
Crea de forma segura el primer usuario administrador.

Uso:
    python crear_admin.py

El script NO expone la contraseña en pantalla ni acepta el rol desde el
usuario: siempre crea rol='admin' y email_verificado=TRUE.
"""

import getpass
import re

from database import get_connection
from seguridad import hash_password

PASSWORD_RE = re.compile(r"^(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,64}$")


def password_valida(password):
    return isinstance(password, str) and bool(PASSWORD_RE.fullmatch(password))


def pedir_dato(mensaje):
    valor = input(mensaje).strip()
    if not valor:
        raise ValueError(f"{mensaje.rstrip(': ')} no puede estar vacío.")
    return valor


def main():
    print("=" * 58)
    print(" CREAR ADMINISTRADOR - FLORÍCOLA LOS ÁLAMOS")
    print("=" * 58)
    print("Este script crea un usuario con rol ADMIN.")
    print("La contraseña debe tener 8-64 caracteres, una mayúscula,")
    print("un número y un signo especial.\n")

    nombres = pedir_dato("Nombres: ")
    apellidos = pedir_dato("Apellidos: ")
    correo = pedir_dato("Correo: ").lower()
    if "@" not in correo or "." not in correo.split("@")[-1]:
        raise ValueError("El correo no parece válido.")

    password = getpass.getpass("Contraseña: ")
    confirmacion = getpass.getpass("Repite la contraseña: ")

    if password != confirmacion:
        raise ValueError("Las contraseñas no coinciden.")
    if not password_valida(password):
        raise ValueError(
            "La contraseña debe tener entre 8 y 64 caracteres, "
            "una mayúscula, un número y un signo especial."
        )

    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, rol FROM usuarios WHERE correo = %s", (correo,))
        existente = cursor.fetchone()
        if existente:
            raise ValueError(
                f"Ya existe un usuario con ese correo (rol actual: {existente['rol']})."
            )

        cursor.execute(
            """
            INSERT INTO usuarios
                (usuario, nombres, apellidos, correo, edad, password, rol, email_verificado)
            VALUES
                (%s, %s, %s, %s, %s, %s, 'admin', TRUE)
            """,
            (correo, nombres, apellidos, correo, 18, hash_password(password)),
        )
        conn.commit()
        print("\nAdministrador creado correctamente.")
        print(f"Correo: {correo}")
        print("Rol: admin")
        print("Correo verificado: sí")
        print("Ya puedes iniciar sesión desde la aplicación.")
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperación cancelada.")
    except Exception as exc:
        print(f"\nERROR: {exc}")
        raise SystemExit(1)
