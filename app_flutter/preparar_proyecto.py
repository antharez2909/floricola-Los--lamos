# Prepara el proyecto Flutter recién creado para hablar con el servidor Flask.
# Uso: dentro de la carpeta del proyecto Flutter, ejecuta:  python preparar_proyecto.py
#
# Hace tres cosas:
#   1. Da permiso de INTERNET a la app (sin esto Android bloquea toda conexión en la versión release).
#   2. Permite HTTP sin cifrar (Flask de desarrollo usa http://, no https://).
#   3. Borra la prueba de ejemplo de Flutter (test/widget_test.dart), que ya no aplica a esta app,
#      e instala los paquetes http y shared_preferences.

import os
import re
import subprocess
import sys

MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")

if not os.path.exists(MANIFEST):
    sys.exit("No encuentro android/app/src/main/AndroidManifest.xml.\n"
             "Ejecuta este script DENTRO de la carpeta del proyecto (la creada con 'flutter create').")

with open(MANIFEST, encoding="utf-8") as f:
    xml = f.read()

if "android.permission.INTERNET" not in xml:
    xml = re.sub(
        r"(<manifest[^>]*>)",
        r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
        xml,
        count=1,
    )
    print("[OK] Permiso INTERNET agregado")

if "usesCleartextTraffic" not in xml:
    xml = xml.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    print("[OK] HTTP sin cifrar permitido (solo para desarrollo)")

# Nombre que se ve debajo del ícono de la app
xml, cambios = re.subn(r'(<application[^>]*?android:label=")[^"]*(")', r'\1Florícola Los Álamos\2', xml, count=1)
if cambios:
    print("[OK] Nombre de la app: Florícola Los Álamos")

with open(MANIFEST, "w", encoding="utf-8") as f:
    f.write(xml)

prueba = os.path.join("test", "widget_test.dart")
if os.path.exists(prueba):
    os.remove(prueba)
    print("[OK] Prueba de ejemplo eliminada")

print("Instalando paquetes (flutter pub add http shared_preferences google_fonts image_picker)...")
resultado = subprocess.run(
    "flutter pub add http shared_preferences google_fonts image_picker", shell=True
)
if resultado.returncode != 0:
    sys.exit(
        "No se pudieron instalar los paquetes. Ejecuta a mano:\n"
        "  flutter pub add http shared_preferences google_fonts image_picker"
    )
print("Listo. Ahora ejecuta: flutter run")
