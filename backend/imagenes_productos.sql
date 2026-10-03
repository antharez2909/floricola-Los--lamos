-- Migración segura para bases existentes.
USE floricola_db;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE productos ADD COLUMN imagen_url VARCHAR(255) NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'productos' AND column_name = 'imagen_url');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
