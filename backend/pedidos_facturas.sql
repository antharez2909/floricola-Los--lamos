-- ======================================================================
-- ESQUEMA: PEDIDOS, DETALLE DE PEDIDO Y FACTURAS
-- ======================================================================
-- Ejecutar UNA vez en MySQL, después de migracion.sql (que ya agrandó
-- la columna 'password'). Este script agrega las tablas que hacían
-- falta para el flujo de compra completo: carrito -> pedido -> factura.
--
-- Diseño (normalizado a 3FN):
--
--   usuarios (ya existía)
--       └─< pedidos            (1 usuario -> muchos pedidos)
--               └─< detalle_pedido   (1 pedido -> muchas líneas)
--                       >── productos (muchas líneas -> 1 producto)
--               └── factura     (1 pedido -> 1 factura, relación 1 a 1)
--
-- Por qué NO existe una tabla "carrito" en la base de datos:
-- el carrito es información TEMPORAL, de un solo uso, que solo le
-- importa al celular mientras la persona decide qué comprar (se arma en
-- la memoria de la app, en Flutter). Guardar eso en MySQL sería una
-- tabla que se llena y se vacía constantemente sin aportar nada una vez
-- que el pedido ya se confirmó. Cuando la persona presiona "Confirmar
-- pedido", TODO el carrito se manda de una vez al servidor, que recién
-- ahí crea las filas permanentes: un pedido y sus líneas en detalle_pedido.
--
-- Por qué el precio se repite en detalle_pedido.precio_unitario en vez
-- de leerlo siempre de productos.precio: para que, si el precio de un
-- producto cambia en el futuro, las facturas VIEJAS seas mantengan con
-- el precio que se pagó en su momento (es una regla contable básica:
-- una factura no debe cambiar de valor después de emitida).

USE floricola_db;

-- ----------------------------------------------------------------------
-- PEDIDOS: la "cabecera" de una compra (quién, cuándo, en qué estado)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedidos (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id    INT NOT NULL,
    fecha         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- ENUM restringe la columna a solo estos 4 valores: evita que, por
    -- un error de tipeo, un pedido quede en un estado inventado como
    -- "entregdo" o "Pendiente " (con espacio).
    estado        ENUM('pendiente', 'listo_para_retiro', 'retirado', 'cancelado')
                  NOT NULL DEFAULT 'pendiente',
    -- 'total' se guarda aquí aunque técnicamente se pueda calcular
    -- sumando detalle_pedido.subtotal: es una redundancia intencional
    -- (desnormalización controlada) para no tener que sumar todas las
    -- líneas cada vez que se lista "mis pedidos" (ver optimización).
    total         DECIMAL(10, 2) NOT NULL,

    CONSTRAINT fk_pedidos_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
        ON DELETE RESTRICT   -- no se puede borrar un usuario que ya tiene pedidos
) ENGINE=InnoDB;

-- Índice para la consulta más frecuente de esta tabla: "los pedidos de
-- este usuario" (usa /api/pedidos cuando el cliente entra a "Mis pedidos").
-- Sin este índice, MySQL tendría que revisar fila por fila (full scan)
-- cada vez que alguien consulta sus pedidos.
CREATE INDEX idx_pedidos_usuario ON pedidos(usuario_id);
-- Índice para cuando el admin filtra los pedidos por estado de preparación/retiro.
CREATE INDEX idx_pedidos_estado ON pedidos(estado);


-- ----------------------------------------------------------------------
-- DETALLE_PEDIDO: cada línea de un pedido ("2 rosas a $2.00 cada una")
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS detalle_pedido (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    pedido_id        INT NOT NULL,
    producto_id      INT NOT NULL,
    cantidad         INT NOT NULL,
    precio_unitario  DECIMAL(10, 2) NOT NULL,  -- precio AL MOMENTO de comprar
    subtotal         DECIMAL(10, 2) NOT NULL,  -- cantidad * precio_unitario

    CONSTRAINT fk_detalle_pedido
        FOREIGN KEY (pedido_id) REFERENCES pedidos(id)
        ON DELETE CASCADE,   -- si se borra un pedido, se borran sus líneas con él
    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (producto_id) REFERENCES productos(id)
        ON DELETE RESTRICT,  -- no se puede borrar un producto ya vendido
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0)
) ENGINE=InnoDB;

-- La consulta típica es "dame todas las líneas de ESTE pedido" (para
-- mostrar el detalle o armar la factura), de ahí este índice.
CREATE INDEX idx_detalle_pedido ON detalle_pedido(pedido_id);
CREATE INDEX idx_detalle_producto ON detalle_pedido(producto_id);


-- ----------------------------------------------------------------------
-- FACTURAS: comprobante emitido para un pedido (relación 1 a 1)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS facturas (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    -- UNIQUE, no solo INT: esto es lo que convierte la relación en 1 a 1.
    -- Sin UNIQUE, nada impediría crear dos facturas para el mismo pedido.
    pedido_id      INT NOT NULL UNIQUE,
    numero         VARCHAR(20) NOT NULL UNIQUE,  -- ej. "F-000123"
    fecha          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total          DECIMAL(10, 2) NOT NULL,

    CONSTRAINT fk_factura_pedido
        FOREIGN KEY (pedido_id) REFERENCES pedidos(id)
        ON DELETE CASCADE
) ENGINE=InnoDB;


-- ----------------------------------------------------------------------
-- ÍNDICE DE APOYO EN PRODUCTOS (para la búsqueda del catálogo)
-- ----------------------------------------------------------------------
-- /api/productos ahora acepta ?buscar=texto (ver api.py). Este índice
-- acelera ese filtro cuando el catálogo crece más allá de unos pocos
-- productos.
--
-- OJO: a diferencia de CREATE TABLE, la sintaxis "IF NOT EXISTS" no
-- existe para CREATE INDEX en todas las versiones de MySQL; por eso
-- este script está pensado para correrse UNA sola vez. Si se corre dos
-- veces, MySQL avisará "Duplicate key name": es inofensivo, solo
-- significa que el índice ya existía.
CREATE INDEX idx_productos_nombre ON productos(nombre);
