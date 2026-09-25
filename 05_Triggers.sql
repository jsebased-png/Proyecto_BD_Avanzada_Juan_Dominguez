-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: 05_Triggers.sql
-- DESCRIPCIÓN: Tablas de auditoría y 20 Triggers para automatización de
--              inventario, auditoría, integridad referencial y reglas de negocio.
-- MOTOR: MySQL 8.0+
-- =============================================================================

USE ecommerce_db;

-- -----------------------------------------------------------------------------
-- TABLAS DE AUDITORÍA Y REGISTRO
-- -----------------------------------------------------------------------------

-- 1. Tabla de auditoría requerida explícitamente: log_cambios_precio
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo DECIMAL(10,2) NOT NULL,
    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario VARCHAR(100) NOT NULL,
    CONSTRAINT fk_logprecio_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 2. Tabla de auditoría de clientes
CREATE TABLE IF NOT EXISTS auditoria_clientes (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL,
    accion VARCHAR(50) NOT NULL DEFAULT 'NUEVO_CLIENTE',
    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

-- 3. Tabla de auditoría de estado de pedidos
CREATE TABLE IF NOT EXISTS auditoria_pedidos (
    id_log_pedido INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    estado_anterior VARCHAR(50) NOT NULL,
    estado_nuevo VARCHAR(50) NOT NULL,
    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

-- 4. Tabla de alertas de stock crítico
CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    sku VARCHAR(50) NOT NULL,
    nombre_producto VARCHAR(150) NOT NULL,
    stock_actual INT NOT NULL,
    umbral_minimo INT NOT NULL,
    mensaje VARCHAR(255) NOT NULL,
    fecha_alerta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_alertastock_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 5. Tabla de archivo de ventas eliminadas
CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_archivo INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_cliente INT NOT NULL,
    id_sucursal INT NOT NULL,
    fecha_venta DATETIME NOT NULL,
    estado VARCHAR(50) NOT NULL,
    total DECIMAL(12,2) NOT NULL,
    fecha_eliminacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_por VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

-- 6. Tabla de auditoría de cambios de permisos
CREATE TABLE IF NOT EXISTS auditoria_permisos (
    id_log_permiso INT AUTO_INCREMENT PRIMARY KEY,
    usuario_afectado VARCHAR(100) NOT NULL,
    rol_asignado VARCHAR(100) NOT NULL,
    accion VARCHAR(50) NOT NULL,
    ejecutado_por VARCHAR(100) NOT NULL,
    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla para rastrear roles asignados y disparar trg_log_permission_changes
CREATE TABLE IF NOT EXISTS asignaciones_roles (
    id_asignacion INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100) NOT NULL,
    rol VARCHAR(100) NOT NULL,
    fecha_asignacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


-- =============================================================================
-- CREACIÓN DE LOS 20 TRIGGERS
-- =============================================================================

DELIMITER //

-- -----------------------------------------------------------------------------
-- 1. trg_audit_precio_producto_after_update
-- Guarda un log de cambios de precios en log_cambios_precio.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update//
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo, fecha_cambio, usuario)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio, NOW(), CURRENT_USER());
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 2. trg_check_stock_before_insert_venta
-- Verifica el stock antes de registrar una venta y arroja error si es insuficiente.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta//
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_actual INT DEFAULT 0;
    
    SELECT stock INTO v_stock_actual
    FROM productos
    WHERE id_producto = NEW.id_producto;
    
    IF v_stock_actual < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error de Inventario: Stock insuficiente para despachar el producto solicitado.';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 3. trg_update_stock_after_insert_venta
-- Decrementa el stock automáticamente después de registrar el detalle de una venta.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta//
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END//


-- -----------------------------------------------------------------------------
-- 4. trg_prevent_delete_categoria_with_products
-- Impide eliminar una categoría si todavía contiene productos asociados.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products//
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_conteo INT DEFAULT 0;
    
    SELECT COUNT(*) INTO v_conteo
    FROM productos
    WHERE id_categoria = OLD.id_categoria;
    
    IF v_conteo > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Integridad Referencial: No se puede eliminar la categoría porque tiene productos asignados.';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 5. trg_log_new_customer_after_insert
-- Registra en auditoria_clientes cada vez que se crea un nuevo cliente.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert//
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_clientes (id_cliente, nombre, email, accion, fecha_registro, usuario)
    VALUES (NEW.id_cliente, CONCAT(NEW.nombre, ' ', NEW.apellido), NEW.email, 'REGISTRO_NUEVO', NOW(), CURRENT_USER());
END//


-- -----------------------------------------------------------------------------
-- 6. trg_update_total_gastado_cliente
-- Actualiza el total_gastado en clientes después de cada compra confirmada.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente//
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> 'Cancelado' AND NEW.total > 0 THEN
        UPDATE clientes
        SET total_gastado = total_gastado + NEW.total
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 7. trg_set_fecha_modificacion_producto
-- Actualiza automáticamente la fecha_modificacion al editar un producto.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto//
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END//


-- -----------------------------------------------------------------------------
-- 8. trg_prevent_negative_stock
-- Impide que el stock de un producto se actualice a un valor negativo.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_negative_stock//
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Violación de Regla de Negocio: El stock no puede ser un valor negativo.';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 9. trg_capitalize_nombre_cliente
-- Convierte a mayúscula la primera letra del nombre y apellido al insertarlo.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente//
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.nombre IS NOT NULL AND CHAR_LENGTH(TRIM(NEW.nombre)) > 0 THEN
        SET NEW.nombre = CONCAT(UPPER(LEFT(TRIM(NEW.nombre), 1)), LOWER(SUBSTRING(TRIM(NEW.nombre), 2)));
    END IF;
    IF NEW.apellido IS NOT NULL AND CHAR_LENGTH(TRIM(NEW.apellido)) > 0 THEN
        SET NEW.apellido = CONCAT(UPPER(LEFT(TRIM(NEW.apellido), 1)), LOWER(SUBSTRING(TRIM(NEW.apellido), 2)));
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 10. trg_recalculate_total_venta_on_detalle_change
-- Recalcula el monto total en la tabla ventas cuando se modifica un detalle_venta.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_insert//
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_insert
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (
        SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0.00)
        FROM detalle_ventas
        WHERE id_venta = NEW.id_venta
    )
    WHERE id_venta = NEW.id_venta;
END//

DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_update//
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_update
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (
        SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0.00)
        FROM detalle_ventas
        WHERE id_venta = NEW.id_venta
    )
    WHERE id_venta = NEW.id_venta;
END//


-- -----------------------------------------------------------------------------
-- 11. trg_log_order_status_change
-- Audita cada cambio de estado en un pedido (ej. 'Procesando' a 'Enviado').
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_order_status_change//
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO auditoria_pedidos (id_venta, estado_anterior, estado_nuevo, fecha_cambio, usuario)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado, NOW(), CURRENT_USER());
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 12. trg_prevent_price_zero_or_less
-- Impide que el precio de un producto se establezca en cero o un valor negativo.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less//
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Precio Inválido: El precio de venta debe ser estrictamente mayor a 0.';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less_update//
CREATE TRIGGER trg_prevent_price_zero_or_less_update
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Precio Inválido: El precio de venta debe ser estrictamente mayor a 0.';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 13. trg_send_stock_alert_on_low_stock
-- Inserta un registro en alertas_stock si el inventario cae a su umbral mínimo o menos.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock//
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock <= NEW.umbral_minimo AND (OLD.stock > OLD.umbral_minimo OR OLD.stock <> NEW.stock) THEN
        INSERT INTO alertas_stock (id_producto, sku, nombre_producto, stock_actual, umbral_minimo, mensaje, fecha_alerta)
        VALUES (
            NEW.id_producto,
            NEW.sku,
            NEW.nombre,
            NEW.stock,
            NEW.umbral_minimo,
            CONCAT('Alerta: Stock crítico para el producto ', NEW.nombre, ' (Disponibles: ', NEW.stock, ', Mínimo: ', NEW.umbral_minimo, ')'),
            NOW()
        );
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 14. trg_archive_deleted_venta
-- Mueve una venta eliminada a la tabla ventas_archivadas en lugar de perderla.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_archive_deleted_venta//
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, id_sucursal, fecha_venta, estado, total, fecha_eliminacion, eliminado_por)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.id_sucursal, OLD.fecha_venta, OLD.estado, OLD.total, NOW(), CURRENT_USER());
END//


-- -----------------------------------------------------------------------------
-- 15. trg_validate_email_format_on_customer
-- Valida el formato del email antes de insertar un nuevo cliente.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer//
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT NEW.email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Formato Inválido: La dirección de correo electrónico proporcionada no es válida.';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 16. trg_update_last_order_date_customer
-- Actualiza la fecha del último pedido en la tabla clientes al registrar una venta.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer//
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET fecha_ultimo_pedido = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END//


-- -----------------------------------------------------------------------------
-- 17. trg_prevent_self_referral
-- Impide que un cliente se referencie a sí mismo en el programa de referidos.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_self_referral//
CREATE TRIGGER trg_prevent_self_referral
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NEW.id_referido_por IS NOT NULL AND NEW.id_referido_por = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Regla Antifraude: Un cliente no puede ser su propio referido.';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 18. trg_log_permission_changes
-- Audita las asignaciones o revocaciones de roles en la tabla auditoria_permisos.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_permission_changes//
CREATE TRIGGER trg_log_permission_changes
AFTER INSERT ON asignaciones_roles
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_permisos (usuario_afectado, rol_asignado, accion, ejecutado_por, fecha_cambio)
    VALUES (NEW.usuario, NEW.rol, 'ASIGNACION_ROL', CURRENT_USER(), NOW());
END//


-- -----------------------------------------------------------------------------
-- 19. trg_assign_default_category_on_null
-- Asigna la categoría "General" si se inserta un producto con categoría NULL o 0.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null//
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    DECLARE v_id_general INT;
    
    IF NEW.id_categoria IS NULL OR NEW.id_categoria <= 0 THEN
        SELECT id_categoria INTO v_id_general
        FROM categorias
        WHERE nombre = 'General'
        LIMIT 1;
        
        IF v_id_general IS NOT NULL THEN
            SET NEW.id_categoria = v_id_general;
        END IF;
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 20. trg_update_producto_count_in_categoria
-- Mantiene actualizado el contador total_productos en la tabla categorias.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_producto_count_insert//
CREATE TRIGGER trg_update_producto_count_insert
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias
    SET total_productos = total_productos + 1
    WHERE id_categoria = NEW.id_categoria;
END//

DROP TRIGGER IF EXISTS trg_update_producto_count_delete//
CREATE TRIGGER trg_update_producto_count_delete
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias
    SET total_productos = GREATEST(0, total_productos - 1)
    WHERE id_categoria = OLD.id_categoria;
END//

DROP TRIGGER IF EXISTS trg_update_producto_count_update//
CREATE TRIGGER trg_update_producto_count_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.id_categoria <> NEW.id_categoria THEN
        UPDATE categorias SET total_productos = GREATEST(0, total_productos - 1) WHERE id_categoria = OLD.id_categoria;
        UPDATE categorias SET total_productos = total_productos + 1 WHERE id_categoria = NEW.id_categoria;
    END IF;
END//

DELIMITER ;