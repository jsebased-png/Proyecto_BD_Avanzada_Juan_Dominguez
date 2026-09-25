-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: 03_Funciones.sql
-- DESCRIPCIÓN: 20 Funciones Definidas por el Usuario (UDFs) para lógica de
--              negocio, cálculos financieros, validaciones y formato.
-- MOTOR: MySQL 8.0+
-- =============================================================================

USE ecommerce_db;

DELIMITER //

-- -----------------------------------------------------------------------------
-- 1. fn_CalcularTotalVenta
-- Calcula el monto total de una venta específica sumando sus detalles.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta//
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT) 
RETURNS DECIMAL(12,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0.00)
    INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;
    RETURN v_total;
END//


-- -----------------------------------------------------------------------------
-- 2. fn_VerificarDisponibilidadStock
-- Valida si hay stock suficiente para un producto y cantidad requerida.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock//
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT) 
RETURNS BOOLEAN
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_stock INT DEFAULT 0;
    SELECT stock INTO v_stock
    FROM productos
    WHERE id_producto = p_id_producto AND activo = TRUE;
    
    IF v_stock IS NOT NULL AND v_stock >= p_cantidad THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 3. fn_ObtenerPrecioProducto
-- Devuelve el precio de venta actual de un producto.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto//
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT) 
RETURNS DECIMAL(10,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_precio DECIMAL(10,2) DEFAULT 0.00;
    SELECT precio INTO v_precio
    FROM productos
    WHERE id_producto = p_id_producto;
    RETURN COALESCE(v_precio, 0.00);
END//


-- -----------------------------------------------------------------------------
-- 4. fn_CalcularEdadCliente
-- Calcula la edad en años de un cliente a partir de su fecha de nacimiento.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente//
CREATE FUNCTION fn_CalcularEdadCliente(p_fecha_nacimiento DATE) 
RETURNS INT
NO SQL
DETERMINISTIC
BEGIN
    IF p_fecha_nacimiento IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE());
END//


-- -----------------------------------------------------------------------------
-- 5. fn_FormatearNombreCompleto
-- Devuelve el nombre y apellido en formato estandarizado (Capitalizado y recortado).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto//
CREATE FUNCTION fn_FormatearNombreCompleto(p_nombre VARCHAR(100), p_apellido VARCHAR(100)) 
RETURNS VARCHAR(205)
NO SQL
DETERMINISTIC
BEGIN
    DECLARE v_nombre_cap VARCHAR(100);
    DECLARE v_apellido_cap VARCHAR(100);
    
    SET v_nombre_cap = CONCAT(UPPER(LEFT(TRIM(p_nombre), 1)), LOWER(SUBSTRING(TRIM(p_nombre), 2)));
    SET v_apellido_cap = CONCAT(UPPER(LEFT(TRIM(p_apellido), 1)), LOWER(SUBSTRING(TRIM(p_apellido), 2)));
    
    RETURN CONCAT(v_nombre_cap, ' ', v_apellido_cap);
END//


-- -----------------------------------------------------------------------------
-- 6. fn_EsClienteNuevo
-- Devuelve VERDADERO si el cliente realizó su primera compra en los últimos 30 días.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_EsClienteNuevo//
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT) 
RETURNS BOOLEAN
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    
    IF v_primera_compra IS NOT NULL AND v_primera_compra >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 7. fn_CalcularCostoEnvio
-- Calcula el costo de envío basado en el peso total acumulado de una venta.
-- Tarifa: Base de $5.00 + $2.50 por kg adicional.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio//
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT) 
RETURNS DECIMAL(10,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_peso_total DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_costo_envio DECIMAL(10,2);
    
    SELECT COALESCE(SUM(d.cantidad * p.peso_kg), 0.00)
    INTO v_peso_total
    FROM detalle_ventas d
    INNER JOIN productos p ON d.id_producto = p.id_producto
    WHERE d.id_venta = p_id_venta;
    
    IF v_peso_total <= 1.00 THEN
        SET v_costo_envio = 5.00;
    ELSE
        SET v_costo_envio = 5.00 + ((v_peso_total - 1.00) * 2.50);
    END IF;
    
    RETURN ROUND(v_costo_envio, 2);
END//


-- -----------------------------------------------------------------------------
-- 8. fn_AplicarDescuento
-- Aplica un porcentaje de descuento a un monto dado.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_AplicarDescuento//
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(10,2), p_porcentaje DECIMAL(5,2)) 
RETURNS DECIMAL(10,2)
NO SQL
DETERMINISTIC
BEGIN
    IF p_porcentaje < 0 OR p_porcentaje > 100 THEN
        RETURN p_monto;
    END IF;
    RETURN ROUND(p_monto * (1 - (p_porcentaje / 100.0)), 2);
END//


-- -----------------------------------------------------------------------------
-- 9. fn_ObtenerUltimaFechaCompra
-- Devuelve la fecha y hora de la última compra confirmada de un cliente.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra//
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT) 
RETURNS DATETIME
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_ultima_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_ultima_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_ultima_fecha;
END//


-- -----------------------------------------------------------------------------
-- 10. fn_ValidarFormatoEmail
-- Comprueba si una cadena tiene una estructura de correo electrónico válida.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail//
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150)) 
RETURNS BOOLEAN
NO SQL
DETERMINISTIC
BEGIN
    IF p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 11. fn_ObtenerNombreCategoria
-- Devuelve el nombre de la categoría a la cual pertenece un producto.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria//
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT) 
RETURNS VARCHAR(100)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_categoria VARCHAR(100);
    SELECT c.nombre INTO v_categoria
    FROM categorias c
    INNER JOIN productos p ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto;
    RETURN COALESCE(v_categoria, 'Sin Categoría');
END//


-- -----------------------------------------------------------------------------
-- 12. fn_ContarVentasCliente
-- Cuenta el número total de compras realizadas por un cliente.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ContarVentasCliente//
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT) 
RETURNS INT
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_conteo INT DEFAULT 0;
    SELECT COUNT(*) INTO v_conteo
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_conteo;
END//


-- -----------------------------------------------------------------------------
-- 13. fn_CalcularDiasDesdeUltimaCompra
-- Devuelve los días transcurridos desde la última compra de un cliente.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra//
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT) 
RETURNS INT
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    
    IF v_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_fecha);
END//


-- -----------------------------------------------------------------------------
-- 14. fn_DeterminarEstadoLealtad
-- Asigna un estado de lealtad (Bronce, Plata, Oro, Platino) según gasto total.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad//
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_total_gastado DECIMAL(12,2)) 
RETURNS VARCHAR(20)
NO SQL
DETERMINISTIC
BEGIN
    IF p_total_gastado >= 5000.00 THEN
        RETURN 'Platino';
    ELSEIF p_total_gastado >= 2500.00 THEN
        RETURN 'Oro';
    ELSEIF p_total_gastado >= 1000.00 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END//


-- -----------------------------------------------------------------------------
-- 15. fn_GenerarSKU
-- Genera un código SKU único basado en el nombre y categoría del producto.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_GenerarSKU//
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(150), p_id_categoria INT) 
RETURNS VARCHAR(50)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_prefijo_cat VARCHAR(10);
    DECLARE v_prefijo_nom VARCHAR(10);
    DECLARE v_aleatorio INT;
    
    SELECT UPPER(SUBSTRING(REGEXP_REPLACE(nombre, '[^A-Za-z]', ''), 1, 3))
    INTO v_prefijo_cat
    FROM categorias
    WHERE id_categoria = p_id_categoria;
    
    IF v_prefijo_cat IS NULL OR CHAR_LENGTH(v_prefijo_cat) < 3 THEN
        SET v_prefijo_cat = 'GEN';
    END IF;
    
    SET v_prefijo_nom = UPPER(SUBSTRING(REGEXP_REPLACE(p_nombre, '[^A-Za-z]', ''), 1, 3));
    IF CHAR_LENGTH(v_prefijo_nom) < 3 THEN
        SET v_prefijo_nom = 'PRD';
    END IF;
    
    SET v_aleatorio = FLOOR(100 + (RAND() * 899));
    
    RETURN CONCAT(v_prefijo_cat, '-', v_prefijo_nom, '-', v_aleatorio);
END//


-- -----------------------------------------------------------------------------
-- 16. fn_CalcularIVA
-- Calcula el impuesto sobre las ventas (IVA del 19%) sobre un monto dado.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularIVA//
CREATE FUNCTION fn_CalcularIVA(p_total DECIMAL(12,2)) 
RETURNS DECIMAL(12,2)
NO SQL
DETERMINISTIC
BEGIN
    IF p_total IS NULL OR p_total < 0 THEN
        RETURN 0.00;
    END IF;
    RETURN ROUND(p_total * 0.19, 2);
END//


-- -----------------------------------------------------------------------------
-- 17. fn_ObtenerStockTotalPorCategoria
-- Suma el inventario de todos los productos activos de una categoría dada.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria//
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT) 
RETURNS INT
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_stock_total INT DEFAULT 0;
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
    FROM productos
    WHERE id_categoria = p_id_categoria AND activo = TRUE;
    RETURN v_stock_total;
END//


-- -----------------------------------------------------------------------------
-- 18. fn_EstimarFechaEntrega
-- Calcula la fecha estimada de entrega de un pedido según la ubicación del cliente.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega//
CREATE FUNCTION fn_EstimarFechaEntrega(p_ciudad VARCHAR(100), p_fecha_venta DATETIME) 
RETURNS DATE
NO SQL
DETERMINISTIC
BEGIN
    DECLARE v_dias_despacho INT;
    DECLARE v_ciudad_clean VARCHAR(100);
    
    SET v_ciudad_clean = LOWER(TRIM(p_ciudad));
    
    CASE 
        WHEN v_ciudad_clean = 'bogotá' OR v_ciudad_clean = 'bogota' THEN
            SET v_dias_despacho = 1;
        WHEN v_ciudad_clean = 'medellín' OR v_ciudad_clean = 'medellin' OR v_ciudad_clean = 'cali' THEN
            SET v_dias_despacho = 2;
        WHEN v_ciudad_clean = 'barranquilla' OR v_ciudad_clean = 'bucaramanga' THEN
            SET v_dias_despacho = 3;
        ELSE
            SET v_dias_despacho = 5;
    END CASE;
    
    RETURN DATE_ADD(DATE(p_fecha_venta), INTERVAL v_dias_despacho DAY);
END//


-- -----------------------------------------------------------------------------
-- 19. fn_ConvertirMoneda
-- Convierte un valor monetario a otra divisa utilizando una tasa de cambio fija.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ConvertirMoneda//
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_tasa_cambio DECIMAL(10,4)) 
RETURNS DECIMAL(12,2)
NO SQL
DETERMINISTIC
BEGIN
    IF p_monto IS NULL OR p_tasa_cambio IS NULL OR p_tasa_cambio <= 0 THEN
        RETURN 0.00;
    END IF;
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END//


-- -----------------------------------------------------------------------------
-- 20. fn_ValidarComplejidadContraseña
-- Verifica si una contraseña cumple con requisitos de longitud (>=8),
-- al menos una mayúscula, una minúscula y un número.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContraseña//
CREATE FUNCTION fn_ValidarComplejidadContraseña(p_contrasena VARCHAR(255)) 
RETURNS BOOLEAN
NO SQL
DETERMINISTIC
BEGIN
    IF CHAR_LENGTH(p_contrasena) < 8 THEN
        RETURN FALSE;
    END IF;
    
    -- Debe contener al menos una mayúscula
    IF NOT p_contrasena REGEXP '[A-Z]' THEN
        RETURN FALSE;
    END IF;
    
    -- Debe contener al menos una minúscula
    IF NOT p_contrasena REGEXP '[a-z]' THEN
        RETURN FALSE;
    END IF;
    
    -- Debe contener al menos un dígito
    IF NOT p_contrasena REGEXP '[0-9]' THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END//

-- Alias de compatibilidad sin tilde/eñe:
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena//
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255)) 
RETURNS BOOLEAN
NO SQL
DETERMINISTIC
BEGIN
    RETURN fn_ValidarComplejidadContraseña(p_contrasena);
END//

DELIMITER ;

