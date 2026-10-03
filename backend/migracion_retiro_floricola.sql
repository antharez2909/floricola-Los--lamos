-- Migración para instalaciones que ya tenían estados de envío.
-- Convierte el flujo anterior a un modelo de retiro presencial en la florícola.
USE floricola_db;

UPDATE pedidos SET estado = 'listo_para_retiro' WHERE estado = 'enviado';
UPDATE pedidos SET estado = 'retirado' WHERE estado = 'entregado';

ALTER TABLE pedidos
  MODIFY estado ENUM('pendiente', 'listo_para_retiro', 'retirado', 'cancelado')
  NOT NULL DEFAULT 'pendiente';
