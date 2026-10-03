import os
from werkzeug.utils import secure_filename

ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

def es_extension_permitida(filename):
    """Verifica si la extensión del archivo está dentro de las permitidas."""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def guardar_imagen(file_storage, folder):
    """
    Guarda un archivo de imagen en la carpeta especificada evitando sobreescrituras.
    Devuelve la ruta relativa orientada a la web (p. ej. 'uploads/galeria/foto.jpg').
    """
    os.makedirs(folder, exist_ok=True)
    
    filename = secure_filename(file_storage.filename)
    base, ext = os.path.splitext(filename)
    
    contador = 1
    nuevo_nombre = filename
    path_completo = os.path.join(folder, nuevo_nombre)
    
    while os.path.exists(path_completo):
        nuevo_nombre = f"{base}_{contador}{ext}"
        path_completo = os.path.join(folder, nuevo_nombre)
        contador += 1
        
    file_storage.save(path_completo)
    
    # Extraer ruta relativa desde la carpeta 'uploads'
    partes = path_completo.replace('\\', '/').split('/uploads/')
    return f"uploads/{partes[-1]}" if len(partes) > 1 else nuevo_nombre
