-- Migración segura para bases existentes.
-- Las cuentas antiguas quedan verificadas para no bloquearlas.
USE floricola_db;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE usuarios ADD COLUMN email_verificado BOOLEAN NOT NULL DEFAULT TRUE',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'usuarios' AND column_name = 'email_verificado');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS verificaciones_email (
    id INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id INT NOT NULL,
    codigo VARCHAR(6) NOT NULL,
    expiracion DATETIME NOT NULL,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_verificacion_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
) ENGINE=InnoDB;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'CREATE INDEX idx_verificaciones_usuario ON verificaciones_email(usuario_id)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'verificaciones_email' AND index_name = 'idx_verificaciones_usuario');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
