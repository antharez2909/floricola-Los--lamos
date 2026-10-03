-- Permite verificar de forma segura una nueva dirección al editar un perfil.
-- Ejecutar una vez en bases de datos existentes, después de email_verificacion.sql.
USE floricola_db;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE verificaciones_email ADD COLUMN correo_destino VARCHAR(150) NULL AFTER usuario_id',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name = 'verificaciones_email'
    AND column_name = 'correo_destino');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
