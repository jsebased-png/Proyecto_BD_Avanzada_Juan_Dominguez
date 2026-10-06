-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: sp_ProcesarDevolucion.sql
-- DESCRIPCIÓN: Proceso automatizado y seguro de devoluciones para Atención al
--              Cliente. Ajusta inventario, actualiza el estado de la venta y
--              deja un registro de auditoría, todo dentro de UNA transacción.
-- MOTOR: MySQL 8.0.16+ (por el CHECK; en versiones anteriores se ignora)
--
-- REQUISITOS (tablas existentes): ventas, detalle_ventas, productos
--
-- ANTES DE EJECUTAR - revisa dos cosas:
--  1) Si ventas.estado es un ENUM, debe incluir los dos estados nuevos. Verifica con:
--        SHOW COLUMNS FROM ventas LIKE 'estado';
--     Si es ENUM, ejecuta (ajustando la lista a los valores que ya tengas):
--        ALTER TABLE ventas MODIFY estado ENUM(
--            'Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado',
--            'Devolución Parcial','Devuelto Totalmente') NOT NULL;
--     Si es VARCHAR no hace falta nada.
--  2) Si ya tienes una tabla devoluciones (p. ej. la de 01) con otra estructura,
--     CREATE TABLE IF NOT EXISTS la dejará intacta y el procedimiento fallará.
--     Renómbrala o migra sus datos antes de ejecutar este script.
--  Este script reemplaza cualquier sp_ProcesarDevolucion anterior (DROP IF EXISTS).
--  Los nombres de tablas van en minúscula, igual que el resto del proyecto
--  (en Linux MySQL distingue mayúsculas: "Productos" y "productos" serían distintas).
-- =============================================================================

USE ecommerce_db;

-- -----------------------------------------------------------------------------
-- 1. TABLA DE AUDITORÍA: devoluciones
-- Cada devolución procesada deja una fila. La columna "estado" indica el estado
-- en que quedó LA VENTA tras esa devolución ('Parcial' o 'Total').
-- Las llaves foráneas usan ON DELETE RESTRICT para que el historial de
-- devoluciones no pueda perderse por borrar una venta o un producto.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS devoluciones (
    id_devolucion     INT AUTO_INCREMENT PRIMARY KEY,
    id_venta          INT NOT NULL,
    id_producto       INT NOT NULL,
    cantidad_devuelta INT NOT NULL,
    fecha_devolucion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado            ENUM('Parcial', 'Total') NOT NULL,

    CONSTRAINT chk_devolucion_cantidad CHECK (cantidad_devuelta > 0),
    CONSTRAINT fk_devolucion_venta FOREIGN KEY (id_venta)
        REFERENCES ventas(id_venta) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_devolucion_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE RESTRICT ON UPDATE CASCADE,

    -- Acelera el cálculo de "cuánto se ha devuelto ya" por venta y producto.
    INDEX idx_devolucion_venta_producto (id_venta, id_producto)
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 2. PROCEDIMIENTO: sp_ProcesarDevolucion
-- Parámetros:
--   p_id_venta          Venta sobre la que se hace la devolución.
--   p_id_producto       Producto que se devuelve.
--   p_cantidad_devuelta Unidades que el cliente devuelve en esta operación.
--
-- Al terminar devuelve un SELECT con el resumen de la operación.
-- -----------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion//
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT,
    IN p_id_producto INT,
    IN p_cantidad_devuelta INT
)
BEGIN
    -- Variables SIN valor por defecto: si un SELECT ... INTO no encuentra filas
    -- quedan en NULL y así podemos detectar "no existe" con IS NULL.
    DECLARE v_estado_venta       VARCHAR(50);
    DECLARE v_cant_comprada      INT;   -- unidades de ESTE producto en la venta
    DECLARE v_cant_ya_devuelta   INT;   -- unidades de ESTE producto ya devueltas antes
    DECLARE v_total_comprado     INT;   -- unidades de TODA la venta
    DECLARE v_total_ya_devuelto  INT;   -- unidades de TODA la venta devueltas antes
    DECLARE v_estado_nuevo_venta VARCHAR(50);
    DECLARE v_estado_devolucion  VARCHAR(10);

    -- -------------------------------------------------------------------------
    -- Manejo de errores: ante CUALQUIER error SQL se deshace todo lo hecho en la
    -- transacción (stock, estado e inserción) y se relanza el error al llamador.
    -- -------------------------------------------------------------------------
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- -------------------------------------------------------------------------
    -- BLOQUE A: Validación de parámetros (antes de abrir la transacción).
    -- -------------------------------------------------------------------------
    IF p_id_venta IS NULL OR p_id_producto IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: la venta y el producto son obligatorios.';
    END IF;

    IF p_cantidad_devuelta IS NULL OR p_cantidad_devuelta <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: la cantidad a devolver debe ser mayor que cero.';
    END IF;

    START TRANSACTION;

    -- -------------------------------------------------------------------------
    -- BLOQUE B: Bloquear y validar la venta.
    -- FOR UPDATE bloquea la fila de la venta: si dos agentes procesan
    -- devoluciones de la misma venta a la vez, la segunda espera a la primera.
    -- Así los cálculos de "ya devuelto" nunca se cruzan.
    -- -------------------------------------------------------------------------
    SELECT estado
    INTO v_estado_venta
    FROM ventas
    WHERE id_venta = p_id_venta
    FOR UPDATE;

    IF v_estado_venta IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: la venta indicada no existe.';
    END IF;

    IF v_estado_venta = 'Cancelado' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: no se puede devolver productos de una venta cancelada.';
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOQUE C: REGLA 1 - La cantidad a devolver no puede exceder lo comprado.
    -- SUM() cubre el caso de que el producto aparezca en varias líneas de la
    -- misma venta. Se descuenta lo ya devuelto en operaciones anteriores, para
    -- que varias devoluciones parciales sumadas tampoco superen lo comprado.
    -- -------------------------------------------------------------------------
    SELECT SUM(cantidad)
    INTO v_cant_comprada
    FROM detalle_ventas
    WHERE id_venta = p_id_venta
      AND id_producto = p_id_producto;

    IF v_cant_comprada IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: el producto no hace parte de la venta indicada.';
    END IF;

    SELECT COALESCE(SUM(cantidad_devuelta), 0)
    INTO v_cant_ya_devuelta
    FROM devoluciones
    WHERE id_venta = p_id_venta
      AND id_producto = p_id_producto;

    IF p_cantidad_devuelta > (v_cant_comprada - v_cant_ya_devuelta) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: la cantidad a devolver excede las unidades compradas pendientes de devolución.';
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOQUE D: Determinar el estado resultante de la venta (REGLA 3).
    -- Se compara el total de unidades de TODA la venta contra el total devuelto
    -- (lo anterior + esta devolución):
    --   - Si ya se devolvió todo        -> 'Devuelto Totalmente' (devolución 'Total')
    --   - Si todavía quedan unidades    -> 'Devolución Parcial'  (devolución 'Parcial')
    -- -------------------------------------------------------------------------
    SELECT SUM(cantidad)
    INTO v_total_comprado
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;

    SELECT COALESCE(SUM(cantidad_devuelta), 0)
    INTO v_total_ya_devuelto
    FROM devoluciones
    WHERE id_venta = p_id_venta;

    IF (v_total_ya_devuelto + p_cantidad_devuelta) >= v_total_comprado THEN
        SET v_estado_nuevo_venta = 'Devuelto Totalmente';
        SET v_estado_devolucion  = 'Total';
    ELSE
        SET v_estado_nuevo_venta = 'Devolución Parcial';
        SET v_estado_devolucion  = 'Parcial';
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOQUE E: REGLA 2 - Reintegrar las unidades al inventario.
    -- -------------------------------------------------------------------------
    UPDATE productos
    SET stock = stock + p_cantidad_devuelta
    WHERE id_producto = p_id_producto;

    -- -------------------------------------------------------------------------
    -- BLOQUE F: REGLA 3 - Actualizar el estado de la venta.
    -- -------------------------------------------------------------------------
    UPDATE ventas
    SET estado = v_estado_nuevo_venta
    WHERE id_venta = p_id_venta;

    -- -------------------------------------------------------------------------
    -- BLOQUE G: REGLA 4 - Registrar la devolución para auditoría.
    -- fecha_devolucion se llena sola (CURRENT_TIMESTAMP).
    -- -------------------------------------------------------------------------
    INSERT INTO devoluciones (id_venta, id_producto, cantidad_devuelta, estado)
    VALUES (p_id_venta, p_id_producto, p_cantidad_devuelta, v_estado_devolucion);

    -- -------------------------------------------------------------------------
    -- BLOQUE H: REGLA 5 - Confirmar. Hasta este punto nada era definitivo: si
    -- cualquiera de los pasos anteriores falló, el handler hizo ROLLBACK.
    -- -------------------------------------------------------------------------
    COMMIT;

    -- Resumen para quien llamó el procedimiento (agente de Atención al Cliente).
    SELECT
        p_id_venta            AS id_venta,
        p_id_producto         AS id_producto,
        p_cantidad_devuelta   AS cantidad_devuelta,
        v_estado_nuevo_venta  AS estado_venta,
        v_estado_devolucion   AS estado_devolucion,
        (v_total_comprado - v_total_ya_devuelto - p_cantidad_devuelta) AS unidades_pendientes_de_devolver;
END//

DELIMITER ;


-- -----------------------------------------------------------------------------
-- 3. EJEMPLOS DE USO (descomenta para probar)
-- -----------------------------------------------------------------------------
-- Devolución de 1 unidad del producto 2 en la venta 1:
-- CALL sp_ProcesarDevolucion(1, 2, 1);
--
-- Ver el historial de devoluciones y el estado de la venta:
-- SELECT * FROM devoluciones ORDER BY fecha_devolucion DESC;
-- SELECT id_venta, estado FROM ventas WHERE id_venta = 1;
