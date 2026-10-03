-- Migración segura para bases existentes.
-- Ejecutar después de pedidos_facturas.sql.
USE floricola_db;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE productos ADD COLUMN tamano_tallo_cm INT NOT NULL DEFAULT 40',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'productos' AND column_name = 'tamano_tallo_cm');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = (SELECT IF(COUNT(*) = 0,
  "ALTER TABLE pedidos ADD COLUMN estado_pago ENUM('pendiente','en_revision','confirmado','rechazado') NOT NULL DEFAULT 'pendiente'",
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'pedidos' AND column_name = 'estado_pago');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS comprobantes_pago (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pedido_id INT NOT NULL,
    ruta_archivo VARCHAR(255) NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_comprobante_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE
) ENGINE=InnoDB;

SET @sql = (SELECT IF(COUNT(*) = 0,
  'CREATE INDEX idx_comprobantes_pedido ON comprobantes_pago(pedido_id)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'comprobantes_pago' AND index_name = 'idx_comprobantes_pedido');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
