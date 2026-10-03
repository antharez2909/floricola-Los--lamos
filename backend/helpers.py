# ======================================================================
# FUNCIONES AUXILIARES (HELPERS) PARA MANEJO DE ARCHIVOS E IMÁGENES
# ======================================================================

import os
from werkzeug.utils import secure_filename

# Conjunto de extensiones de archivo permitidas para la carga de imágenes
EXTENSIONES_PERMITIDAS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}


def es_extension_permitida(filename):
    """
    Verifica si un nombre de archivo tiene una extensión válida dentro del conjunto permitido.
    
    :param filename: Nombre original del archivo (ej. 'foto.jpg')
    :return: True si la extensión es válida, False en caso contrario.
    """
    # Comprueba que exista un punto en el nombre y valida la extensión en minúsculas
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in EXTENSIONES_PERMITIDAS


def guardar_imagen(file, folder_path):
    """
    Valida, desinfecta el nombre y almacena una imagen cargada en la carpeta especificada.
    
    :param file: Objeto de archivo recibido de la petición HTTP (FileStorage)
    :param folder_path: Ruta del directorio de destino (ej. 'static/uploads/galeria')
    :return: Nombre del archivo guardado si fue exitoso, o None si el archivo no es válido.
    """
    # Verifica que el archivo no sea nulo y cumpla con las extensiones permitidas
    if file and es_extension_permitida(file.filename):
        # Limpia y desinfecta el nombre del archivo para prevenir ataques de Directory Traversal
        filename = secure_filename(file.filename)
        
        # Crea el directorio de destino y sus carpetas padres si aún no existen
        os.makedirs(folder_path, exist_ok=True)
        
        # Construye la ruta completa de almacenamiento en el sistema de archivos
        file_path = os.path.join(folder_path, filename)
        
        # Guarda físicamente el archivo en el disco
        file.save(file_path)
        
        # Retorna el nombre final del archivo guardado
        return filename
        
    # Retorna None si el archivo no pasó la validación
    return None

import random

def generar_codigo_6_digitos():
    """Genera un código aleatorio de 6 dígitos numéricos para verificación."""
    return str(random.randint(100000, 999999))

def enviar_codigo_verificacion(email, codigo):
    """
    Simulación de envío de correo de verificación.
    Imprime en la consola el código para que puedas probar la API sin configurar un servidor SMTP.
    """
    print(f"\n==========================================")
    print(f"[CORREO SIMULADO] Para: {email}")
    print(f"[CÓDIGO DE VERIFICACIÓN]: {codigo}")
    print(f"==========================================\n")
    return True