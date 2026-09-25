-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: 07_Procedimientos_Almacenados.sql
-- DESCRIPCIÓN: 20 Procedimientos Almacenados con control transaccional,
--              manejo de excepciones y lógica de operaciones comerciales.
-- MOTOR: MySQL 8.0+
-- =============================================================================
USE ecommerce_db;
DELIMITER // -- -----------------------------------------------------------------------------
-- 1. sp_RealizarNuevaVenta
-- Procesa una nueva venta de forma transaccional, validando inventario,
-- creando la orden y sus detalles correspondientes.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta // CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_sucursal INT,
    IN p_id_producto INT,
    IN p_cantidad INT,
    OUT p_id_venta_generada INT
) BEGIN
DECLARE v_stock_disponible INT DEFAULT 0;
DECLARE v_precio_actual DECIMAL(10, 2) DEFAULT 0.00;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
-- Validar existencia y stock del producto con bloqueo pesimista
SELECT stock,
    precio INTO v_stock_disponible,
    v_precio_actual
FROM productos
WHERE id_producto = p_id_producto
    AND activo = TRUE FOR
UPDATE;
IF v_stock_disponible IS NULL THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Error: El producto especificado no existe o está descontinuado.';
END IF;
IF v_stock_disponible < p_cantidad THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Error: Stock insuficiente para procesar la transacción.';
END IF;
-- Insertar encabezado de la venta
INSERT INTO ventas (
        id_cliente,
        id_sucursal,
        fecha_venta,
        estado,
        total
    )
VALUES (
        p_id_cliente,
        p_id_sucursal,
        NOW(),
        'Procesando',
        ROUND(v_precio_actual * p_cantidad, 2)
    );
SET p_id_venta_generada = LAST_INSERT_ID();
-- Insertar detalle de venta (el trigger decrementa stock y actualiza cliente)
INSERT INTO detalle_ventas (
        id_venta,
        id_producto,
        cantidad,
        precio_unitario_congelado
    )
VALUES (
        p_id_venta_generada,
        p_id_producto,
        p_cantidad,
        v_precio_actual
    );
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 2. sp_AgregarNuevoProducto
-- Inserta un nuevo producto al catálogo validando sus atributos obligatorios.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto // CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_id_categoria INT,
    IN p_id_proveedor INT,
    IN p_sku VARCHAR(50),
    IN p_nombre VARCHAR(150),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10, 2),
    IN p_costo DECIMAL(10, 2),
    IN p_stock INT,
    IN p_umbral_minimo INT,
    IN p_peso_kg DECIMAL(6, 2),
    OUT p_id_producto_creado INT
) BEGIN IF p_precio <= 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'El precio debe ser estrictamente positivo.';
END IF;
IF p_costo < 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'El costo no puede ser negativo.';
END IF;
IF p_stock < 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'El stock inicial no puede ser negativo.';
END IF;
INSERT INTO productos (
        id_categoria,
        id_proveedor,
        sku,
        nombre,
        descripcion,
        precio,
        costo,
        stock,
        umbral_minimo,
        peso_kg,
        activo
    )
VALUES (
        p_id_categoria,
        p_id_proveedor,
        p_sku,
        p_nombre,
        p_descripcion,
        p_precio,
        p_costo,
        COALESCE(p_stock, 0),
        COALESCE(p_umbral_minimo, 10),
        COALESCE(p_peso_kg, 1.00),
        TRUE
    );
SET p_id_producto_creado = LAST_INSERT_ID();
END // -- -----------------------------------------------------------------------------
-- 3. sp_ActualizarDireccionCliente
-- Actualiza la dirección principal de envío y ciudad de un cliente.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente // CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion TEXT,
    IN p_ciudad VARCHAR(100),
    IN p_pais VARCHAR(100)
) BEGIN
UPDATE clientes
SET direccion_envio = p_nueva_direccion,
    ciudad = COALESCE(p_ciudad, ciudad),
    pais = COALESCE(p_pais, pais)
WHERE id_cliente = p_id_cliente;
END // -- -----------------------------------------------------------------------------
-- 4. sp_ProcesarDevolucion
-- Gestiona la devolución de un producto, ajustando el inventario y calculando
-- el monto de crédito o reembolso al cliente.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion // CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT,
    IN p_id_producto INT,
    IN p_cantidad_devolver INT,
    IN p_motivo TEXT,
    OUT p_monto_credito DECIMAL(10, 2)
) BEGIN
DECLARE v_cantidad_comprada INT DEFAULT 0;
DECLARE v_precio_congelado DECIMAL(10, 2) DEFAULT 0.00;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
-- Validar que el producto haya sido parte de la venta
SELECT cantidad,
    precio_unitario_congelado INTO v_cantidad_comprada,
    v_precio_congelado
FROM detalle_ventas
WHERE id_venta = p_id_venta
    AND id_producto = p_id_producto;
IF v_cantidad_comprada IS NULL
OR v_cantidad_comprada < p_cantidad_devolver THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Error: La cantidad a devolver excede lo registrado en la orden.';
END IF;
SET p_monto_credito = ROUND(v_precio_congelado * p_cantidad_devolver, 2);
-- Registrar la devolución
INSERT INTO devoluciones (
        id_venta,
        id_producto,
        cantidad,
        motivo,
        monto_credito,
        fecha_devolucion
    )
VALUES (
        p_id_venta,
        p_id_producto,
        p_cantidad_devolver,
        p_motivo,
        p_monto_credito,
        NOW()
    );
-- Reintegrar el stock al producto
UPDATE productos
SET stock = stock + p_cantidad_devolver
WHERE id_producto = p_id_producto;
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 5. sp_ObtenerHistorialComprasCliente
-- Devuelve el historial completo de ventas y productos adquiridos por un cliente.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente // CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT) BEGIN
SELECT v.id_venta,
    v.fecha_venta,
    v.estado,
    s.nombre AS sucursal,
    p.sku,
    p.nombre AS producto,
    d.cantidad,
    d.precio_unitario_congelado,
    (d.cantidad * d.precio_unitario_congelado) AS subtotal,
    v.total AS total_orden
FROM ventas v
    INNER JOIN sucursales s ON v.id_sucursal = s.id_sucursal
    INNER JOIN detalle_ventas d ON v.id_venta = d.id_venta
    INNER JOIN productos p ON d.id_producto = p.id_producto
WHERE v.id_cliente = p_id_cliente
ORDER BY v.fecha_venta DESC,
    v.id_venta DESC;
END // -- -----------------------------------------------------------------------------
-- 6. sp_AjustarNivelStock
-- Permite ajustar manualmente el inventario de un producto registrando auditoría.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock // CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo VARCHAR(255),
    IN p_usuario VARCHAR(100)
) BEGIN
DECLARE v_stock_anterior INT DEFAULT 0;
IF p_nuevo_stock < 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'El nuevo stock no puede ser un valor negativo.';
END IF;
SELECT stock INTO v_stock_anterior
FROM productos
WHERE id_producto = p_id_producto;
-- Registrar en tabla de ajustes de inventario
INSERT INTO ajustes_inventario (
        id_producto,
        stock_anterior,
        nuevo_stock,
        motivo,
        usuario,
        fecha_ajuste
    )
VALUES (
        p_id_producto,
        v_stock_anterior,
        p_nuevo_stock,
        p_motivo,
        COALESCE(p_usuario, CURRENT_USER()),
        NOW()
    );
-- Actualizar stock
UPDATE productos
SET stock = p_nuevo_stock
WHERE id_producto = p_id_producto;
END // -- -----------------------------------------------------------------------------
-- 7. sp_EliminarClienteDeFormaSegura
-- Anonimiza la información personal de un cliente para mantener integridad
-- referencial con ventas históricas (derecho al olvido / GDPR).
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura // CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT) BEGIN
UPDATE clientes
SET nombre = 'Cliente',
    apellido = 'Anonimizado',
    email = CONCAT('anonimo_', p_id_cliente, '@anonimizado.local'),
    contraseña = '$2b$12$CUENTA_ANONIMIZADA_SIN_ACCESO_LOCAL',
    direccion_envio = 'DIRECCION_ANONIMIZADA',
    fecha_nacimiento = NULL,
    activo = FALSE
WHERE id_cliente = p_id_cliente;
END // -- -----------------------------------------------------------------------------
-- 8. sp_AplicarDescuentoPorCategoria
-- Aplica un porcentaje de descuento a todos los productos de una categoría.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria // CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje_descuento DECIMAL(5, 2)
) BEGIN IF p_porcentaje_descuento <= 0
OR p_porcentaje_descuento >= 100 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'El porcentaje de descuento debe estar entre 0.01 y 99.99.';
END IF;
UPDATE productos
SET precio = ROUND(
        precio * (1 - (p_porcentaje_descuento / 100.0)),
        2
    )
WHERE id_categoria = p_id_categoria
    AND activo = TRUE;
END // -- -----------------------------------------------------------------------------
-- 9. sp_GenerarReporteMensualVentas
-- Genera un reporte detallado con las métricas comerciales de un mes dado.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas // CREATE PROCEDURE sp_GenerarReporteMensualVentas(IN p_mes INT, IN p_anio INT) BEGIN
SELECT p_anio AS anio,
    p_mes AS mes,
    COUNT(DISTINCT v.id_venta) AS total_pedidos,
    COUNT(DISTINCT v.id_cliente) AS clientes_unicos,
    COALESCE(SUM(v.total), 0.00) AS ingresos_totales,
    COALESCE(ROUND(AVG(v.total), 2), 0.00) AS ticket_promedio,
    COALESCE(SUM(d.cantidad), 0) AS unidades_totales_vendidas,
    COALESCE(
        SUM(
            d.cantidad * (d.precio_unitario_congelado - p.costo)
        ),
        0.00
    ) AS margen_bruto_total
FROM ventas v
    LEFT JOIN detalle_ventas d ON v.id_venta = d.id_venta
    LEFT JOIN productos p ON d.id_producto = p.id_producto
WHERE MONTH(v.fecha_venta) = p_mes
    AND YEAR(v.fecha_venta) = p_anio
    AND v.estado <> 'Cancelado';
END // -- -----------------------------------------------------------------------------
-- 10. sp_CambiarEstadoPedido
-- Cambia el estado de un pedido (ej. de 'Procesando' a 'Enviado').
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido // CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado ENUM(
        'Pendiente de Pago',
        'Procesando',
        'Enviado',
        'Entregado',
        'Cancelado'
    )
) BEGIN
UPDATE ventas
SET estado = p_nuevo_estado
WHERE id_venta = p_id_venta;
END // -- -----------------------------------------------------------------------------
-- 11. sp_RegistrarNuevoCliente
-- Registra un nuevo cliente validando que el correo electrónico no exista.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente // CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena VARCHAR(255),
    IN p_direccion TEXT,
    IN p_ciudad VARCHAR(100),
    IN p_fecha_nacimiento DATE,
    IN p_id_referido INT,
    OUT p_id_cliente_creado INT
) BEGIN
DECLARE v_existe INT DEFAULT 0;
SELECT COUNT(*) INTO v_existe
FROM clientes
WHERE email = p_email;
IF v_existe > 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Error: Ya existe una cuenta registrada con este correo electrónico.';
END IF;
INSERT INTO clientes (
        nombre,
        apellido,
        email,
        contraseña,
        direccion_envio,
        ciudad,
        fecha_nacimiento,
        id_referido_por,
        activo
    )
VALUES (
        p_nombre,
        p_apellido,
        p_email,
        p_contrasena,
        p_direccion,
        COALESCE(p_ciudad, 'Bogotá'),
        p_fecha_nacimiento,
        p_id_referido,
        TRUE
    );
SET p_id_cliente_creado = LAST_INSERT_ID();
END // -- -----------------------------------------------------------------------------
-- 12. sp_ObtenerDetallesProductoCompleto
-- Devuelve toda la información del producto, su categoría, proveedor y reseñas.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto // CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT) BEGIN
SELECT p.id_producto,
    p.sku,
    p.nombre AS producto,
    p.descripcion,
    p.precio,
    p.costo,
    (p.precio - p.costo) AS margen_unitario,
    p.stock,
    p.umbral_minimo,
    p.peso_kg,
    p.vistas,
    p.activo,
    c.nombre AS categoria,
    prov.nombre AS proveedor,
    prov.email_contacto AS email_proveedor,
    prov.telefono_contacto AS tel_proveedor,
    COALESCE(ROUND(AVG(r.calificacion), 1), 0.0) AS calificacion_promedio,
    COUNT(r.id_resena) AS total_resenas
FROM productos p
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
    INNER JOIN proveedores prov ON p.id_proveedor = prov.id_proveedor
    LEFT JOIN resenas_productos r ON p.id_producto = r.id_producto
WHERE p.id_producto = p_id_producto
GROUP BY p.id_producto,
    c.nombre,
    prov.nombre,
    prov.email_contacto,
    prov.telefono_contacto;
END // -- -----------------------------------------------------------------------------
-- 13. sp_FusionarCuentasCliente
-- Fusiona dos cuentas duplicadas, trasladando ventas, carritos y reseñas
-- de la cuenta origen a la cuenta destino, y desactivando la cuenta origen.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente // CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_origen INT,
    IN p_id_cliente_destino INT
) BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
IF p_id_cliente_origen = p_id_cliente_destino THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'No se puede fusionar una cuenta consigo misma.';
END IF;
START TRANSACTION;
-- Reasignar ventas históricas
UPDATE ventas
SET id_cliente = p_id_cliente_destino
WHERE id_cliente = p_id_cliente_origen;
-- Reasignar carritos de compras
UPDATE carrito_compras
SET id_cliente = p_id_cliente_destino
WHERE id_cliente = p_id_cliente_origen;
-- Reasignar reseñas de productos
UPDATE resenas_productos
SET id_cliente = p_id_cliente_destino
WHERE id_cliente = p_id_cliente_origen;
-- Recalcular total gastado en cliente destino
UPDATE clientes
SET total_gastado = (
        SELECT COALESCE(SUM(total), 0.00)
        FROM ventas
        WHERE id_cliente = p_id_cliente_destino
            AND estado <> 'Cancelado'
    )
WHERE id_cliente = p_id_cliente_destino;
-- Desactivar y marcar la cuenta origen
UPDATE clientes
SET activo = FALSE,
    email = CONCAT(
        'fusionado_con_',
        p_id_cliente_destino,
        '_',
        email
    )
WHERE id_cliente = p_id_cliente_origen;
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 14. sp_AsignarProductoAProveedor
-- Reasigna un producto a un proveedor diferente.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor // CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_nuevo_proveedor INT
) BEGIN
DECLARE v_proveedor_existe INT DEFAULT 0;
SELECT COUNT(*) INTO v_proveedor_existe
FROM proveedores
WHERE id_proveedor = p_id_nuevo_proveedor;
IF v_proveedor_existe = 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'El nuevo proveedor especificado no existe.';
END IF;
UPDATE productos
SET id_proveedor = p_id_nuevo_proveedor
WHERE id_producto = p_id_producto;
END // -- -----------------------------------------------------------------------------
-- 15. sp_BuscarProductos
-- Búsqueda avanzada de catálogo con filtros dinámicos por término, categoría y precio.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_BuscarProductos // CREATE PROCEDURE sp_BuscarProductos(
    IN p_termino VARCHAR(100),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10, 2),
    IN p_precio_max DECIMAL(10, 2),
    IN p_solo_disponibles BOOLEAN
) BEGIN
SELECT p.id_producto,
    p.sku,
    p.nombre,
    p.descripcion,
    p.precio,
    p.stock,
    c.nombre AS categoria,
    prov.nombre AS proveedor
FROM productos p
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
    INNER JOIN proveedores prov ON p.id_proveedor = prov.id_proveedor
WHERE p.activo = TRUE
    AND (
        p_termino IS NULL
        OR p.nombre LIKE CONCAT('%', p_termino, '%')
        OR p.descripcion LIKE CONCAT('%', p_termino, '%')
    )
    AND (
        p_id_categoria IS NULL
        OR p.id_categoria = p_id_categoria
    )
    AND (
        p_precio_min IS NULL
        OR p.precio >= p_precio_min
    )
    AND (
        p_precio_max IS NULL
        OR p.precio <= p_precio_max
    )
    AND (
        p_solo_disponibles IS FALSE
        OR p.stock > 0
    )
ORDER BY p.precio ASC;
END // -- -----------------------------------------------------------------------------
-- 16. sp_ObtenerDashboardAdmin
-- Devuelve un resumen gerencial instantáneo con los principales indicadores del e-commerce.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin // CREATE PROCEDURE sp_ObtenerDashboardAdmin() BEGIN
SELECT (
        SELECT COALESCE(SUM(total), 0.00)
        FROM ventas
        WHERE DATE(fecha_venta) = CURDATE()
            AND estado <> 'Cancelado'
    ) AS ventas_hoy,
    (
        SELECT COUNT(*)
        FROM ventas
        WHERE DATE(fecha_venta) = CURDATE()
            AND estado <> 'Cancelado'
    ) AS transacciones_hoy,
    (
        SELECT COALESCE(SUM(total), 0.00)
        FROM ventas
        WHERE MONTH(fecha_venta) = MONTH(CURDATE())
            AND YEAR(fecha_venta) = YEAR(CURDATE())
            AND estado <> 'Cancelado'
    ) AS ventas_mes_actual,
    (
        SELECT COUNT(*)
        FROM clientes
        WHERE activo = TRUE
    ) AS total_clientes_activos,
    (
        SELECT COUNT(*)
        FROM productos
        WHERE stock <= umbral_minimo
            AND activo = TRUE
    ) AS productos_alerta_stock,
    (
        SELECT COUNT(*)
        FROM ventas
        WHERE estado = 'Pendiente de Pago'
    ) AS ordenes_pendientes_pago;
END // -- -----------------------------------------------------------------------------
-- 17. sp_ProcesarPago
-- Simula la recepción y validación de un pago para una venta en estado pendiente.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarPago // CREATE PROCEDURE sp_ProcesarPago(
    IN p_id_venta INT,
    IN p_monto_pagado DECIMAL(12, 2),
    OUT p_resultado VARCHAR(100)
) BEGIN
DECLARE v_total_venta DECIMAL(12, 2);
DECLARE v_estado_actual VARCHAR(50);
SELECT total,
    estado INTO v_total_venta,
    v_estado_actual
FROM ventas
WHERE id_venta = p_id_venta;
IF v_total_venta IS NULL THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'La venta solicitada no existe.';
END IF;
IF v_estado_actual <> 'Pendiente de Pago' THEN
SET p_resultado = CONCAT(
        'ERROR: La orden ya está en estado ',
        v_estado_actual
    );
ELSEIF p_monto_pagado < v_total_venta THEN
SET p_resultado = 'ERROR: El monto pagado es inferior al total facturado.';
ELSE
UPDATE ventas
SET estado = 'Procesando'
WHERE id_venta = p_id_venta;
SET p_resultado = 'PAGO_CONFIRMADO_EXITOSAMENTE';
END IF;
END // -- -----------------------------------------------------------------------------
-- 18. sp_AñadirReseñaProducto
-- Permite registrar una calificación y reseña únicamente si el cliente
-- adquirió previamente el producto en una venta entregada.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AñadirReseñaProducto // CREATE PROCEDURE sp_AñadirReseñaProducto(
    IN p_id_cliente INT,
    IN p_id_producto INT,
    IN p_calificacion INT,
    IN p_comentario TEXT
) BEGIN
DECLARE v_comprado INT DEFAULT 0;
IF p_calificacion < 1
OR p_calificacion > 5 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'La calificación debe estar entre 1 y 5 estrellas.';
END IF;
-- Validar compra verificada
SELECT COUNT(*) INTO v_comprado
FROM ventas v
    INNER JOIN detalle_ventas d ON v.id_venta = d.id_venta
WHERE v.id_cliente = p_id_cliente
    AND d.id_producto = p_id_producto
    AND v.estado = 'Entregado';
IF v_comprado = 0 THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'No autorizado: Solo clientes con compra entregada pueden reseñar este producto.';
END IF;
INSERT INTO resenas_productos (
        id_producto,
        id_cliente,
        calificacion,
        comentario,
        fecha_resena
    )
VALUES (
        p_id_producto,
        p_id_cliente,
        p_calificacion,
        p_comentario,
        NOW()
    );
END // -- Alias de compatibilidad sin tilde/eñe:
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto // CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_cliente INT,
    IN p_id_producto INT,
    IN p_calificacion INT,
    IN p_comentario TEXT
) BEGIN CALL sp_AñadirReseñaProducto(
    p_id_cliente,
    p_id_producto,
    p_calificacion,
    p_comentario
);
END // -- -----------------------------------------------------------------------------
-- 19. sp_ObtenerProductosRelacionados
-- Devuelve recomendaciones de productos basadas en compras concurrentes.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados // CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT, IN p_limite INT) BEGIN
SELECT p.id_producto,
    p.sku,
    p.nombre AS producto_recomendado,
    c.nombre AS categoria,
    p.precio,
    COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas d1
    INNER JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta
    AND d1.id_producto <> d2.id_producto
    INNER JOIN productos p ON d2.id_producto = p.id_producto
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
WHERE d1.id_producto = p_id_producto
    AND p.activo = TRUE
GROUP BY p.id_producto,
    p.sku,
    p.nombre,
    c.nombre,
    p.precio
ORDER BY veces_comprados_juntos DESC
LIMIT p_limite;
END // -- -----------------------------------------------------------------------------
-- 20. sp_MoverProductosEntreCategorias
-- Reasigna en masa todos los productos de una categoría origen a una destino.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias // CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT
) BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
IF p_id_categoria_origen = p_id_categoria_destino THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'La categoría de origen y destino deben ser distintas.';
END IF;
START TRANSACTION;
UPDATE productos
SET id_categoria = p_id_categoria_destino
WHERE id_categoria = p_id_categoria_origen;
-- Actualizar conteos de productos en ambas categorías
UPDATE categorias
SET total_productos = (
        SELECT COUNT(*)
        FROM productos
        WHERE id_categoria = p_id_categoria_origen
    )
WHERE id_categoria = p_id_categoria_origen;
UPDATE categorias
SET total_productos = (
        SELECT COUNT(*)
        FROM productos
        WHERE id_categoria = p_id_categoria_destino
    )
WHERE id_categoria = p_id_categoria_destino;
COMMIT;
END // DELIMITER;