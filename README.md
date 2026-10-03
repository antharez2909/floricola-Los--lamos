# Florícola Los Álamos — App móvil (Flutter) + API (Flask)

## Descripción de la aplicación

Florícola Los Álamos es una aplicación digital para apoyar la gestión y venta de productos de una florícola. Los clientes pueden consultar el catálogo, crear una cuenta, agregar productos al carrito, realizar pedidos, enviar comprobantes de pago por transferencia y revisar sus compras. Los pedidos se coordinan para retiro presencial en la florícola.

La aplicación también incluye herramientas administrativas para gestionar productos, clientes, pedidos y pagos. Está desarrollada con Flutter, una API en Flask y una base de datos MySQL, y contempla su uso en Flutter Web y Android.

Durante su desarrollo se utilizaron herramientas de inteligencia artificial como apoyo en aproximadamente un 60 % del trabajo. La IA se empleó como asistencia en el proceso de creación; la aplicación no ofrece funciones de inteligencia artificial a sus usuarios.

Esta versión es una base funcional para el emprendimiento y podrá evolucionar con futuras actualizaciones, como nuevos medios de pago, reportes de ventas y mejoras de experiencia, según las necesidades del negocio.

Dos carpetas:

- `backend/` → archivos **nuevos o modificados** de tu proyecto Flask (agrega la API JSON `/api/...`).
- `app_flutter/` → la app Android en Flutter (`lib/` + un script de preparación).

## 1. Backend (Flask)

1. **Copia** los archivos de `backend/` dentro de tu carpeta `proyecto_floricola_los_alamos/`, reemplazando `app.py` y `database.py`.
   Tus plantillas (`templates/`) y `static/` no se tocan: la web sigue funcionando.
2. En la terminal, con el venv activo:
   ```powershell
   venv\Scripts\activate
   pip uninstall -y mysql-conector-python
   pip install -r requirements.txt
   ```
   (El paquete `mysql-conector-python`, con la "n" mal escrita, no es el oficial y hay que quitarlo.)
3. Crea el archivo `.env`: copia `.env.example` como `.env` y complétalo (clave de MySQL, un `SECRET_KEY` largo).
   Agrega una línea `.env` a tu `.gitignore` para no subirlo a GitHub.
4. En MySQL, ejecuta los scripts necesarios **en este orden** (con un cliente de MySQL, por ejemplo
   `mysql -u root -p < schema_inicial.sql`, o pegando el contenido en phpMyAdmin/Workbench):
   1. `schema_inicial.sql` — crea la base `floricola_db` y las tablas `usuarios` y `productos`.
      **Solo hace falta si tu base de datos es nueva**; si ya tenías estas tablas de antes, sáltalo.
   2. `migracion.sql` — agranda la columna `password` (por si tu base es de antes de este cambio;
      en una base creada con `schema_inicial.sql` ya viene del tamaño correcto, así que es un no-op seguro).
   3. `pedidos_facturas.sql` — crea las tablas `pedidos`, `detalle_pedido` y `facturas` para el flujo de compra.
   4. `pagos_transferencia.sql` — agrega el tamaño de tallo a los productos y todo el flujo de pago por
      transferencia (estado de pago en los pedidos + tabla `comprobantes_pago`).
   5. `email_verificacion.sql`, `perfil_usuario.sql` y `recuperacion_password.sql` — solo para bases de datos existentes:
      preparan la verificación del correo, la recuperación de contraseña y la confirmación segura al cambiarlo desde el perfil.
      En una base nueva, `schema_inicial.sql` ya crea las columnas necesarias.
5. (Opcional) `python migrar_passwords.py` convierte de una vez todas las contraseñas antiguas a hash.
   Si no lo haces, cada cuenta se convierte sola la primera vez que inicia sesión.
6. Arranca el servidor: `python app.py`
   Prueba en el navegador: `http://localhost:5000/api/status`
7. No hay ningún usuario administrador por defecto: regístrate desde la app o la web y luego,
   en MySQL, ejecuta `UPDATE usuarios SET rol = 'admin' WHERE correo = 'tu_correo@ejemplo.com';`
   (el mismo paso está explicado al final de `schema_inicial.sql`).

> **Seguridad:** la clave de `root` de MySQL estaba escrita en `database.py` y subida a GitHub.
> Cámbiala en MySQL aunque ya no esté en el código: el historial de Git la conserva.

## 2. App Flutter

1. Crea un proyecto Flutter nuevo (así se genera la carpeta `android/`):
   ```powershell
   flutter create --org ec.losalamos floricola_app
   ```
2. Copia el contenido de `app_flutter/lib/` dentro de `floricola_app/lib/` (reemplaza `main.dart`).
   Copia también `preparar_proyecto.py` a `floricola_app/`.
3. Entra a la carpeta y ejecuta el script (permisos de red + instala `http`, `shared_preferences`,
   `google_fonts` e `image_picker`):
   ```powershell
   cd floricola_app
   python preparar_proyecto.py
   ```
4. Ejecuta la app con el servidor Flask encendido:
   - **Flutter Web en la misma PC que Flask:** usa por defecto `http://localhost:5000`.
   - **Emulador de Android:** `flutter run` (usa `10.0.2.2`, que apunta a tu PC).
   - **Celular real o navegador en otro dispositivo:** conéctalo al **mismo Wi-Fi** que el PC,
     mira la IP actual del PC con `ipconfig` (Adaptador de Wi-Fi → "Dirección IPv4") y ejecuta:
     ```powershell
     flutter run --dart-define=API_BASE_URL=http://192.168.0.5:5000
     ```
     Sustituye `192.168.0.5` por la IP que muestre tu PC. Si no conecta, permite Python en el
     Firewall de Windows (redes privadas) y comprueba que `http://<IP-del-PC>:5000/api/me`
     responde (401 sin sesión es normal y confirma que Flask es alcanzable).

## Pago por transferencia bancaria

1. El cliente confirma el carrito (`POST /api/pedidos`): el pedido queda con `estado_pago = "pendiente"`.
2. La app lo manda directo a la pantalla de pago (`lib/screens/comprobante_screen.dart`), que muestra los
   datos de la cuenta y deja elegir una foto del comprobante. Los datos bancarios del proyecto
   ya están configurados en `lib/screens/comprobante_screen.dart`; no es necesario modificar el código para cambiarlos.
3. Al subir la foto (`POST /api/pedidos/<id>/comprobante`, como `multipart/form-data`), el pedido pasa a
   `estado_pago = "en_revision"`. La imagen se guarda en `backend/uploads/comprobantes/` (agrega esa
   carpeta a tu `.gitignore`: son fotos de comprobantes de clientes, no algo para subir a GitHub).
4. El admin la revisa desde el detalle del pedido (botón "Ver comprobante") y decide con
   `PUT /api/pedidos/<id>/pago` (`{"accion": "confirmar"}` o `{"accion": "rechazar"}`).
   - Confirmar → `estado_pago = "confirmado"` (la compra queda completada).
   - Rechazar → `estado_pago = "rechazado"`; el cliente puede subir un comprobante nuevo.

## Endpoints de la API (`/api/...`)

| Método | Ruta | Quién | Qué hace |
|---|---|---|---|
| POST | `/login` | público | Inicia sesión, devuelve un token |
| POST | `/registro` | público | Crea una cuenta (rol `cliente`) |
| POST | `/password/recuperar` | público | Solicita por correo un código temporal para restablecer la contraseña |
| POST | `/password/restablecer` | público | Cambia la contraseña usando correo, código y contraseña nueva |
| GET | `/me` | con sesión | Datos del usuario del token |
| PUT | `/me` | con sesión | Edita sus datos personales; los cambios de correo requieren verificación |
| GET | `/productos?pagina=&por_pagina=&buscar=` | con sesión | Catálogo paginado, con búsqueda |
| POST | `/productos` | admin | Crea un producto |
| PUT | `/productos/<id>` | admin | Edita un producto |
| DELETE | `/productos/<id>` | admin | Elimina un producto |
| POST | `/pedidos` | con sesión | Confirma el carrito: crea pedido + detalle + factura (transacción) |
| GET | `/pedidos?pagina=&por_pagina=&estado=` | con sesión | Cliente: sus pedidos. Admin: todos, con filtro de estado |
| GET | `/pedidos/<id>` | con sesión | Detalle de un pedido con sus líneas y su factura |
| PUT | `/pedidos/<id>/estado` | admin | Cambia el estado de un pedido |
| GET | `/clientes?pagina=&por_pagina=&buscar=` | admin | Lista de usuarios, paginada y con búsqueda |
| PUT | `/clientes/<id>` | admin | Edita datos personales de un usuario; los cambios de correo requieren verificación |
| POST | `/pedidos/<id>/comprobante` | con sesión (dueño) | Sube la foto del comprobante (multipart, campo `imagen`) |
| GET | `/pedidos/<id>/comprobante` | con sesión (dueño o admin) | Devuelve la imagen del comprobante más reciente |
| PUT | `/pedidos/<id>/pago` | admin | Confirma o rechaza el pago (`{"accion": "confirmar"\|"rechazar"}`) |
| GET | `/inicio/contenido` | con sesión | Devuelve el fondo y la galería del Inicio |
| GET | `/inicio/imagenes/<nombre>` | público | Sirve una imagen configurada para el Inicio |
| POST / DELETE | `/inicio/fondo` | admin | Cambia o quita el fondo del Inicio (multipart, campo `imagen`) |
| POST | `/inicio/galeria` | admin | Agrega una foto a la galería (multipart, campo `imagen`; máximo 12) |
| DELETE | `/inicio/galeria/<nombre>` | admin | Quita una foto de la galería |

Todas las rutas (salvo login/registro) exigen la cabecera `Authorization: Bearer <token>`.
Los errores siempre llegan como `{"error": "..."}` con el código HTTP correspondiente
(400 dato inválido, 401 sin sesión, 403 sin permiso, 404 no existe).

## Optimización aplicada

- **Paginación:** `/productos` y `/clientes` devuelven `{"datos": [...], "total": N, "por_pagina": N}`
  en vez de la tabla completa; Flutter pide más páginas con el botón "Cargar más".
- **Filtros de búsqueda:** `?buscar=texto` en productos y clientes agrega un `WHERE ... LIKE`,
  para que MySQL filtre (usando el índice `idx_productos_nombre`) en vez de traer todo y filtrar en el teléfono.
- **Índices:** `idx_pedidos_usuario`, `idx_pedidos_estado`, `idx_detalle_pedido`,
  `idx_detalle_producto`, `idx_productos_nombre` (ver `pedidos_facturas.sql`).
- **Transacción con bloqueo de filas:** `POST /pedidos` usa `SELECT ... FOR UPDATE` sobre cada
  producto antes de descontar stock, para que dos compras simultáneas de la última unidad no dejen
  el inventario en negativo, y hace *rollback* completo si algún producto no tiene stock suficiente.

## Diseño

En **Mi cuenta**, cada persona puede editar su usuario, nombres, apellidos, edad y correo.
El administrador también puede editar esos datos desde **Clientes**. Por seguridad,
el correo nuevo solo se activa después de ingresar el código enviado a esa dirección;
el rol y la contraseña no se modifican desde esta pantalla.

El administrador puede cambiar el fondo de toda la app y agregar o quitar hasta 12 fotos
en la pestaña Inicio. La imagen se muestra con baja opacidad detrás de las pantallas y
con intensidad completa en el destacado de Inicio. Los archivos y su configuración se guardan en
`backend/uploads/inicio/` (máximo 5 MB por imagen; JPG, JPEG, PNG o WEBP). El Inicio
usa un fondo degradado si todavía no se ha cargado una imagen. La carpeta `uploads/`
está excluida de Git; conserva una copia de esa carpeta si necesitas respaldar las imágenes.

La app usa una identidad propia, definida en `lib/theme.dart`, en vez de los colores
y tipografía por defecto de Flutter:

- **Colores:** verde bosque `#1B4332` y verde principal `#2D6A4F` (de tu marca), fondo
  verde lima suave `#F0F4B8`, tarjetas blancas con borde fino en vez de sombras.
- **Tipografía:** `Fraunces` (serif) para el nombre de la app y los títulos de pantalla;
  `Public Sans` para el resto. Se cargan con el paquete `google_fonts`.
- **Logotipo:** un monograma "LA" (`lib/app_logo.dart`) en vez de un ícono genérico.

Para cambiar el color principal o la tipografía, edita `AppColors` y `AppTheme.light()`
en `lib/theme.dart`; el resto de las pantallas ya toman sus estilos de ahí.

En **Productos**, al agregar un artículo se puede indicar la cantidad de una sola vez;
la app limita el ingreso al stock disponible y muestra el aviso general
“Artículos agregados al carrito”. El administrador puede cargar una imagen de fondo
para toda la app y fotos para su galería desde la pestaña Inicio.

## Qué incluye

| Pantalla | Cliente | Admin |
|---|---|---|
| Login y registro | ✔ | ✔ |
| Inicio (acerca de, contacto) | ✔ | ✔ |
| Productos (ver) | ✔ | ✔ |
| Productos (agregar / eliminar) | — | ✔ |
| Productos (buscar) | ✔ | ✔ |
| Productos (editar, con tamaño de tallo en cm) | — | ✔ |
| Carrito (agregar, quitar, cambiar cantidad) | ✔ | — |
| Confirmar pedido (crea pedido + factura) | ✔ | — |
| Pagar por transferencia (subir comprobante) | ✔ | — |
| Revisar y confirmar/rechazar el pago | — | ✔ |
| Mis pedidos (ver historial y detalle) | ✔ | — |
| Pedidos (ver todos, filtrar y cambiar estado) | — | ✔ |
| Clientes (lista de usuarios, con búsqueda) | — | ✔ |
| Mi cuenta y cerrar sesión | ✔ | ✔ |

## Cómo funciona el carrito

El carrito no se almacena en MySQL como una tabla independiente. Se mantiene en memoria para que
la interfaz responda inmediatamente y también se persiste localmente con `SharedPreferences`,
separado por correo de usuario. Por ello, si la app se cierra y vuelve a abrirse, el carrito puede
recuperarse. Al cerrar sesión se limpia el carrito activo para evitar mezclar cuentas.

Al presionar "Confirmar pedido", el carrito se manda de una sola vez a `POST /api/pedidos`. El
backend crea las filas permanentes (pedido, detalle y factura) dentro de una transacción. El precio
y el stock definitivos se vuelven a leer desde MySQL: la app nunca manda precios al servidor, solo
`producto_id` y `cantidad`.

## Cambios de seguridad respecto a tu versión

- Contraseñas con hash (scrypt) en vez de texto plano; las cuentas antiguas se migran solas.
- Credenciales y `SECRET_KEY` salen del código y van al `.env`.
- Solo el admin puede agregar o eliminar productos (antes cualquier usuario con sesión podía).
- `debug` apagado por defecto (actívalo con `FLASK_DEBUG=1` en el `.env` mientras desarrollas).
- Antes de publicar la app de verdad, el servidor debe usar **HTTPS**; el permiso de HTTP sin cifrar es solo para desarrollo.

## Retiro en la florícola

La aplicación no ofrece envíos a domicilio. Los pedidos confirmados se preparan para **retiro presencial en la Florícola Los Álamos**.

El estado del pedido sigue el flujo: `pendiente` → `listo_para_retiro` → `retirado`, con `cancelado` como estado alternativo cuando corresponde. No se registra dirección de domicilio ni costo de envío.

## Nuevas funciones de correo

La versión actual incorpora verificación de correo para cuentas nuevas, recuperación de contraseña por correo y envío automático del comprobante de compra cuando un administrador confirma un pago.

1. Ejecuta `email_verificacion.sql`, `perfil_usuario.sql` y `recuperacion_password.sql` una sola vez si la base de datos ya existía.
2. En `backend/.env`, configura las variables `SMTP_*`. Si todavía no tienes ese archivo, copia `backend/.env.example` como `backend/.env`. El mismo SMTP se usa para verificación, recuperación y comprobantes.
3. Instala las dependencias con `pip install -r requirements.txt`; ahora se incluye ReportLab para generar el PDF.
4. Para Gmail, activa la verificación en dos pasos y crea una contraseña de aplicación en la configuración de seguridad de tu cuenta Google. Pon el correo en `SMTP_USER` y `SMTP_FROM`, y esa contraseña de aplicación en `SMTP_PASSWORD`; no pongas tu contraseña normal de Gmail en el proyecto.

Desde la pantalla de inicio de sesión se puede solicitar un código de recuperación. El código vence en 15 minutos,
se guarda como hash, permite hasta cinco intentos y solo se puede usar una vez. La respuesta al solicitarlo
no confirma si el correo está registrado. La contraseña nueva debe tener entre 8 y 64 caracteres, una mayúscula,
un número y un signo especial.

El PDF es un comprobante interno de compra, no una factura electrónica tributaria.

## Crear el usuario administrador

El registro público siempre crea usuarios con rol `cliente`. Para crear un administrador, usa el script del backend; no hace falta editar la base de datos manualmente.

1. Configura primero `backend/.env` con tus datos de MySQL.
2. Abre PowerShell dentro de la carpeta `backend`.
3. Ejecuta:

```powershell
python crear_admin.py
```

4. El script solicitará nombres, apellidos, correo y contraseña. La contraseña debe cumplir las mismas reglas de la aplicación: **8 a 64 caracteres, al menos una mayúscula, un número y un signo especial**.
5. El administrador se crea directamente con `rol='admin'` y `email_verificado=TRUE`, por lo que puede iniciar sesión inmediatamente.

La contraseña nunca se guarda en texto plano: el script utiliza el mismo hash de seguridad que el registro normal.

## Imágenes de productos

La aplicación ahora permite que un administrador seleccione una imagen al crear o editar una flor/producto.

### Base de datos existente

Si ya tienes creada la base `floricola_db`, ejecuta una sola vez:

```sql
SOURCE backend/imagenes_productos.sql;
```

o abre `backend/imagenes_productos.sql` en MySQL Workbench y ejecútalo.

La columna `productos.imagen_url` guarda únicamente el nombre generado por el servidor. Las imágenes se almacenan en `backend/uploads/productos/`, que está excluida de Git.

### Desde la aplicación

1. Inicia sesión como administrador.
2. Entra a **Productos**.
3. Pulsa **Nuevo producto** o **Editar**.
4. Toca el recuadro de la foto.
5. Selecciona una imagen de la galería.
6. Guarda el producto.

Formatos aceptados: JPG, JPEG, PNG y WEBP. El servidor mantiene un límite global de 5 MB por petición.

Los productos antiguos sin imagen continúan funcionando y muestran el ícono de flor hasta que se les asigne una foto.


## Migraciones SQL: base nueva vs. base existente

### Base de datos nueva
Ejecuta en este orden:
1. `schema_inicial.sql`
2. `pedidos_facturas.sql`
3. `pagos_transferencia.sql`

No es necesario ejecutar `email_verificacion.sql` ni `imagenes_productos.sql`, porque el esquema inicial ya contiene esas columnas/tablas.

### Base de datos existente
Ejecuta, según las funcionalidades que te falten:
- `email_verificacion.sql`
- `imagenes_productos.sql`
- `pagos_transferencia.sql`

Las migraciones anteriores fueron hechas para poder ejecutarse más de una vez sin volver a agregar columnas existentes.

### Contraseñas
La política actual es: **8 a 64 caracteres**, al menos una mayúscula, un número y un signo especial. Se usa la misma regla en API, web, Flutter y creación del administrador.

### Usuario
El campo técnico `usuarios.usuario` se conserva por compatibilidad con el esquema, pero se guarda el **correo electrónico** como identificador de usuario. La interfaz no pide un nombre de usuario separado.

### Imágenes de productos
Las imágenes se guardan en `backend/uploads/productos/`, se limitan a 5 MB y admiten JPG, JPEG, PNG y WEBP. Esa carpeta está excluida de Git.

### Verificación de correo

En `schema_inicial.sql`, `email_verificado` tiene `DEFAULT FALSE` porque una cuenta nueva debe
verificar su correo. La API y la web también fuerzan `FALSE` al registrar. El script
`crear_admin.py` establece `TRUE` explícitamente para el administrador creado por el responsable
del sistema. En bases existentes, `email_verificacion.sql` conserva `DEFAULT TRUE` al agregar la
columna para no bloquear cuentas antiguas; los nuevos registros siguen estableciendo `FALSE`.

## Arquitectura y decisiones de diseño

La documentación técnica completa se encuentra en `docs/`: arquitectura, casos de uso, modelo
entidad-relación y secuencia de compra/pago. Los diagramas están escritos en Mermaid para que
puedan visualizarse en GitHub o en editores compatibles.

### Capas

```text
Flutter
  ↓ HTTP/JSON + Bearer token
Flask REST API
  ↓ reglas de negocio + transacciones
MySQL
  ↘ SMTP / almacenamiento de imágenes
```

### Connection pooling

`backend/database.py` utiliza `MySQLConnectionPool` de `mysql-connector-python`. El tamaño por
defecto es 5 conexiones y puede ajustarse mediante `DB_POOL_SIZE` en `.env`. Esto evita abrir una
conexión TCP nueva para cada consulta y mejora el comportamiento cuando existen varias peticiones
simultáneas.

### Control de concurrencia

El checkout usa transacciones y `SELECT ... FOR UPDATE` para proteger el stock. Además, antes de
confirmar o rechazar un pago, el backend bloquea el pedido y exige que su estado actual sea
`en_revision`; así se evita confirmar dos veces el mismo pago y enviar comprobantes duplicados.

## Pruebas automatizadas

El proyecto incluye pruebas unitarias para seguridad, validaciones y carrito.

### Backend

Desde `backend/` con el entorno virtual activo:

```powershell
pytest -q
```

### Flutter

Después de crear el proyecto Flutter completo y copiar `app_flutter/lib/`:

```powershell
flutter test
```

Las pruebas no sustituyen las pruebas manuales de MySQL, SMTP, carga de archivos y flujo completo
de compra.

## Prueba de carga

Se incluye `tools/load_test.py` como herramienta de medición para un entorno de pruebas. Por
defecto prueba un endpoint de lectura y permite aumentar la concurrencia sin crear pedidos ni
modificar stock. Ejemplo:

```powershell
python tools/load_test.py --url http://127.0.0.1:5000/api/status --users 10 --requests 100
```

Para probar endpoints protegidos se puede proporcionar un token de prueba mediante `--token`. Las
pruebas de creación de pedidos y pagos deben hacerse sobre una base de datos de pruebas, nunca sobre
la base de datos real del proyecto.
