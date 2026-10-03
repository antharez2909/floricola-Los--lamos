-- Migración para habilitar la recuperación de contraseña en bases existentes.
USE floricola_db;

CREATE TABLE IF NOT EXISTS codigos_recuperacion (
    usuario_id INT PRIMARY KEY,
    codigo_hash CHAR(64) NOT NULL,
    expiracion DATETIME NOT NULL,
    intentos TINYINT UNSIGNED NOT NULL DEFAULT 0,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_recuperacion_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
) ENGINE=InnoDB;
