-- ======================================================================
-- ESQUEMA INICIAL: base de datos, USUARIOS y PRODUCTOS
-- ======================================================================
-- Este es el PRIMER script que se debe correr, en una base de datos
-- MySQL nueva (una PC recién configurada, o la primera vez que se monta
-- el proyecto). Si tu base de datos YA tenía estas tablas de antes
-- (por ejemplo, si vienes trabajando en esto desde hace semanas), NO
-- hace falta correr este archivo: sáltalo y ve directo a migracion.sql.
--
-- Orden completo para una base de datos nueva:
--   1. schema_inicial.sql      (base + usuarios + productos + correo/recuperación)
--   2. pedidos_facturas.sql    (pedidos, detalle y facturas)
--   3. pagos_transferencia.sql (tamaño de tallo + pagos)
--   4. migracion.sql           (compatible con bases antiguas)
-- Para una base NUEVA no hace falta ejecutar email_verificacion.sql,
-- perfil_usuario.sql, recuperacion_password.sql ni imagenes_productos.sql:
-- esas migraciones son para bases ya existentes.

CREATE DATABASE IF NOT EXISTS floricola_db;
USE floricola_db;

-- ----------------------------------------------------------------------
-- USUARIOS: tanto clientes como administradores viven en esta misma
-- tabla; lo único que los distingue es la columna 'rol'.
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    usuario   VARCHAR(100) NOT NULL,
    nombres   VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    -- UNIQUE: MySQL rechaza automáticamente un segundo registro con el
    -- mismo correo (además de la validación que ya hace la API).
    correo    VARCHAR(150) NOT NULL UNIQUE,
    edad      INT NOT NULL DEFAULT 18,
    -- VARCHAR(255) desde el inicio: un hash de contraseña (scrypt) mide
    -- hasta ~160 caracteres. Con esto ya no hace falta correr
    -- migracion.sql en una base nueva, pero no está de más tenerlo.
    password  VARCHAR(255) NOT NULL,
    rol       ENUM('cliente', 'admin') NOT NULL DEFAULT 'cliente',
    -- TRUE mantiene compatibles las cuentas antiguas; el registro nuevo
    -- fuerza FALSE y exige verificar el correo antes de continuar.
    email_verificado BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------
-- PRODUCTOS: el catálogo de flores.
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    nombre   VARCHAR(150) NOT NULL,
    cantidad INT NOT NULL DEFAULT 0,
    precio   DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    tamano_tallo_cm INT NOT NULL DEFAULT 40,
    imagen_url VARCHAR(255) NULL
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------
-- VERIFICACIONES DE CORREO
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS verificaciones_email (
    id INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id INT NOT NULL,
    correo_destino VARCHAR(150) NULL,
    codigo VARCHAR(6) NOT NULL,
    expiracion DATETIME NOT NULL,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_verificacion_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS codigos_recuperacion (
    usuario_id INT PRIMARY KEY,
    codigo_hash CHAR(64) NOT NULL,
    expiracion DATETIME NOT NULL,
    intentos TINYINT UNSIGNED NOT NULL DEFAULT 0,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_recuperacion_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
) ENGINE=InnoDB;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'CREATE INDEX idx_verificaciones_usuario ON verificaciones_email(usuario_id)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'verificaciones_email' AND index_name = 'idx_verificaciones_usuario');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ----------------------------------------------------------------------
-- (Opcional) Un par de productos de ejemplo, para no arrancar con el
-- catálogo vacío. Bórralos o cámbialos por los tuyos cuando quieras.
-- ----------------------------------------------------------------------
INSERT INTO productos (nombre, cantidad, precio) VALUES
    ('Rosa roja', 100, 2.00),
    ('Tulipán', 50, 3.50),
    ('Girasol', 40, 4.00);

-- ----------------------------------------------------------------------
-- Cómo crear tu primer usuario administrador
-- ----------------------------------------------------------------------
-- No se crea un admin aquí porque su contraseña debe quedar guardada
-- con hash, y este script no puede calcular ese hash (eso lo hace
-- Python, no MySQL). Los pasos son:
-- Para crear el primer administrador usa backend/crear_admin.py.
-- La aplicación pública siempre registra rol='cliente'.
