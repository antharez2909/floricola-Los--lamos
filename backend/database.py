# ======================================================================
# CONEXIÓN A LA BASE DE DATOS (MySQL)
# ======================================================================
# Este archivo tiene una sola responsabilidad: abrir una conexión a MySQL
# cuando alguien la pida. Tanto app.py (la web) como api.py (la app móvil)
# llaman a get_connection() cada vez que necesitan leer o escribir datos.
#
# Las credenciales (usuario, contraseña, host de MySQL) NO están escritas
# aquí: se leen del archivo .env, para poder subir este código a GitHub
# sin exponer la contraseña real de la base de datos.

import os

import mysql.connector
from mysql.connector import pooling

try:
    # python-dotenv lee el archivo .env y carga sus líneas como si fueran
    # variables de entorno del sistema operativo (os.environ). Así, en
    # desarrollo, no hay que configurar nada a mano en Windows/Mac/Linux:
    # basta con tener un archivo .env en la carpeta del proyecto.
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
except ImportError:
    # Si no está instalado python-dotenv, el programa igual funciona,
    # siempre que las variables ya estén definidas de otra forma (por
    # ejemplo, en un servidor de producción que las inyecta directamente).
    pass


_POOL = None

def _get_pool():
    """Obtiene un pool reutilizable de conexiones MySQL.

    El pool evita abrir una conexión TCP nueva para cada consulta. El tamaño
    es configurable con DB_POOL_SIZE y, por defecto, usa 5 conexiones.
    """
    global _POOL
    if _POOL is None:
        password = os.environ.get("DB_PASSWORD")
        if password is None:
            raise RuntimeError("Falta DB_PASSWORD. Copia .env.example a .env y complétalo.")
        _POOL = pooling.MySQLConnectionPool(
            pool_name="floricola_pool",
            pool_size=int(os.environ.get("DB_POOL_SIZE", "5")),
            pool_reset_session=True,
            host=os.environ.get("DB_HOST", "127.0.0.1"),
            port=int(os.environ.get("DB_PORT", "3307")),
            user=os.environ.get("DB_USER", "root"),
            password=password,
            database=os.environ.get("DB_NAME", "floricola_db"),
        )
    return _POOL


def get_connection():
    """Devuelve una conexión reutilizable del pool MySQL."""
    return _get_pool().get_connection()
