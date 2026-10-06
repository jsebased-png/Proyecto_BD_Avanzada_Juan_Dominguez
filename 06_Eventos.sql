-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: 06_Eventos.sql
-- DESCRIPCIÓN: Activación del planificador, creación de tablas de soporte y
--              20 Eventos Programados para automatización del mantenimiento,
--              reportes analíticos y tareas periódicas de negocio.
-- MOTOR: MySQL 8.0+
-- ORDEN DE EJECUCIÓN: 01 -> 03 -> 05 -> 07 -> 06 -> 04 -> 02
-- NOTAS:
--  * Un evento que falla NO muestra error en el cliente: solo queda en el log de
--    errores del servidor. Prueba cada evento a mano ejecutando antes su SELECT
--    interno.
--  * Requiere las funciones de 03 (fn_DeterminarEstadoLealtad).
--  * Las tablas kpis_mensuales, reporte_rendimiento_proveedores y alertas_fraude
--    se definen SOLO aquí (ya no deben existir en 01).
-- =============================================================================
USE ecommerce_db;
-- -----------------------------------------------------------------------------
-- ACTIVACIÓN DEL PLANIFICADOR DE EVENTOS
-- Requiere un usuario con SYSTEM_VARIABLES_ADMIN o SUPER (si no, error 1227).
-- SET PERSIST lo conserva tras reiniciar el servidor (SET GLOBAL lo perdía).
-- Alternativa: poner  event_scheduler=ON  en la sección [mysqld] de my.cnf.
-- -----------------------------------------------------------------------------
SET PERSIST event_scheduler = ON;
-- -----------------------------------------------------------------------------
-- TABLAS DE DESTINO Y SOPORTE PARA EVENTOS
-- -----------------------------------------------------------------------------
-- 1. Tabla explícitamente requerida: reporte_ventas_semanales
CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    anio INT NOT NULL,
    semana INT NOT NULL,
    total_ventas DECIMAL(12, 2) NOT NULL,
    cantidad_pedidos INT NOT NULL,
    ticket_promedio DECIMAL(10, 2) NOT NULL,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 2. Tabla de resumen diario de ventas
CREATE TABLE IF NOT EXISTS resumen_ventas_diarias (
    id_resumen INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATE NOT NULL UNIQUE,
    total_ventas DECIMAL(12, 2) NOT NULL,
    total_pedidos INT NOT NULL,
    productos_vendidos INT NOT NULL,
    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 3. Tabla para lista de reorden de inventario
CREATE TABLE IF NOT EXISTS reorden_inventario (
    id_reorden INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    sku VARCHAR(50) NOT NULL,
    nombre_producto VARCHAR(150) NOT NULL,
    stock_actual INT NOT NULL,
    umbral_minimo INT NOT NULL,
    cantidad_a_pedir INT NOT NULL,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reorden_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;
-- 4. Tabla de KPIs mensuales consolidados
CREATE TABLE IF NOT EXISTS kpis_mensuales (
    id_kpi INT AUTO_INCREMENT PRIMARY KEY,
    anio INT NOT NULL,
    mes INT NOT NULL,
    ingresos_totales DECIMAL(12, 2) NOT NULL,
    margen_bruto DECIMAL(12, 2) NOT NULL,
    ticket_promedio DECIMAL(10, 2) NOT NULL,
    total_clientes_activos INT NOT NULL,
    pedidos_completados INT NOT NULL,
    fecha_calculo DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 5. Tabla de ranking periódico de productos
CREATE TABLE IF NOT EXISTS ranking_productos (
    id_ranking INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    nombre_producto VARCHAR(150) NOT NULL,
    posicion INT NOT NULL,
    unidades_vendidas INT NOT NULL,
    ingresos_generados DECIMAL(12, 2) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ranking_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;
-- 6. Tabla de desempeño mensual de proveedores
CREATE TABLE IF NOT EXISTS reporte_rendimiento_proveedores (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor INT NOT NULL,
    nombre_proveedor VARCHAR(150) NOT NULL,
    anio INT NOT NULL,
    mes INT NOT NULL,
    unidades_vendidas INT NOT NULL,
    total_facturado DECIMAL(12, 2) NOT NULL,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reprend_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;
-- 7. Tabla para monitoreo del tamaño de la BD
CREATE TABLE IF NOT EXISTS log_tamano_bd (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    tamano_mb DECIMAL(10, 2) NOT NULL,
    total_tablas INT NOT NULL,
    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 8. Tabla para detección de sospechas de fraude
CREATE TABLE IF NOT EXISTS alertas_fraude (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    cantidad_intentos INT NOT NULL,
    fecha_deteccion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_alertafraude_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;
-- 9. Tabla de cupones de cumpleaños generados
CREATE TABLE IF NOT EXISTS cupones_cumpleanos (
    id_cupon INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    codigo_cupon VARCHAR(50) NOT NULL,
    descuento_pct DECIMAL(5, 2) NOT NULL DEFAULT 15.00,
    fecha_expiracion DATE NOT NULL,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_cupon_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;
-- 10. Tabla de archivo histórico para logs viejos
CREATE TABLE IF NOT EXISTS historial_logs_archivo (
    id_archivo INT AUTO_INCREMENT PRIMARY KEY,
    origen_log VARCHAR(50) NOT NULL,
    detalle_log TEXT NOT NULL,
    fecha_original DATETIME NOT NULL,
    fecha_archivado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 11. Tabla de log de auditoría para inconsistencias de datos
CREATE TABLE IF NOT EXISTS log_inconsistencias_datos (
    id_inconsistencia INT AUTO_INCREMENT PRIMARY KEY,
    tipo VARCHAR(100) NOT NULL,
    descripcion TEXT NOT NULL,
    fecha_revision DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 12. Tabla de respaldo lógico de ventas
CREATE TABLE IF NOT EXISTS backup_logico_ventas (
    id_backup INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_cliente INT NOT NULL,
    fecha_venta DATETIME NOT NULL,
    total DECIMAL(12, 2) NOT NULL,
    fecha_snapshot DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 13. Tabla de vista materializada simulada para resúmenes por categoría
CREATE TABLE IF NOT EXISTS vm_resumen_categoria (
    id_categoria INT PRIMARY KEY,
    nombre_categoria VARCHAR(100) NOT NULL,
    total_productos INT NOT NULL,
    unidades_vendidas INT NOT NULL,
    ingresos_acumulados DECIMAL(12, 2) NOT NULL,
    ultima_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- 14. Tabla auxiliar temporal para registro de limpieza
CREATE TABLE IF NOT EXISTS staging_limpieza_temp (
    id INT AUTO_INCREMENT PRIMARY KEY,
    dato VARCHAR(100),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
-- =============================================================================
-- CREACIÓN DE LOS 20 EVENTOS PROGRAMADOS
-- =============================================================================
DELIMITER // -- -----------------------------------------------------------------------------
-- 1. evt_generate_weekly_sales_report
-- Genera el reporte consolidado de ventas de la semana anterior cada lunes.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_weekly_sales_report // CREATE EVENT evt_generate_weekly_sales_report ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-05 01:00:00' DO BEGIN
INSERT INTO reporte_ventas_semanales (
        anio,
        semana,
        total_ventas,
        cantidad_pedidos,
        ticket_promedio
    )
SELECT YEAR(DATE_SUB(NOW(), INTERVAL 1 WEEK)),
    WEEK(DATE_SUB(NOW(), INTERVAL 1 WEEK), 1),
    COALESCE(SUM(total), 0.00),
    COUNT(id_venta),
    COALESCE(ROUND(AVG(total), 2), 0.00)
FROM ventas
WHERE fecha_venta >= DATE_SUB(NOW(), INTERVAL 1 WEEK)
    AND estado <> 'Cancelado';
END // -- -----------------------------------------------------------------------------
-- 2. evt_cleanup_temp_tables_daily
-- Borra registros temporales de staging diariamente a medianoche.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily // CREATE EVENT evt_cleanup_temp_tables_daily ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 00:05:00' DO BEGIN TRUNCATE TABLE staging_limpieza_temp;
END // -- -----------------------------------------------------------------------------
-- 3. evt_archive_old_logs_monthly
-- Archiva logs de más de 6 meses en tablas históricas y los remueve del log activo.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_archive_old_logs_monthly // CREATE EVENT evt_archive_old_logs_monthly ON SCHEDULE EVERY 1 MONTH STARTS '2026-01-01 02:00:00' DO BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
-- Archivar cambios de precios con más de 6 meses
INSERT INTO historial_logs_archivo (origen_log, detalle_log, fecha_original)
SELECT 'log_cambios_precio',
    CONCAT(
        'Prod ID: ',
        id_producto,
        ' Anterior: ',
        precio_anterior,
        ' Nuevo: ',
        precio_nuevo,
        ' Usuario: ',
        usuario
    ),
    fecha_cambio
FROM log_cambios_precio
WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
DELETE FROM log_cambios_precio
WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 4. evt_deactivate_expired_promotions_hourly
-- Desactiva códigos de descuento que han llegado a su fecha de vencimiento.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly // CREATE EVENT evt_deactivate_expired_promotions_hourly ON SCHEDULE EVERY 1 HOUR DO BEGIN
UPDATE promociones
SET activo = FALSE
WHERE fecha_fin < NOW()
    AND activo = TRUE;
END // -- -----------------------------------------------------------------------------
-- 5. evt_recalculate_customer_loyalty_tiers_nightly
-- Recalcula el nivel de lealtad de todos los clientes cada noche a las 02:30 AM.
-- Usa fn_DeterminarEstadoLealtad (03) para que los umbrales en COP estén en un
-- solo lugar. 'Platino' debe existir en el ENUM de clientes.nivel_lealtad.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly // CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 02:30:00' DO BEGIN
UPDATE clientes c
SET c.nivel_lealtad = fn_DeterminarEstadoLealtad(c.total_gastado);
END // -- -----------------------------------------------------------------------------
-- 6. evt_generate_reorder_list_daily
-- Crea diariamente una lista de productos cuyo stock está debajo del umbral mínimo.
-- DELETE + INSERT dentro de una transacción: si el INSERT falla, la lista anterior
-- se conserva (TRUNCATE hace commit implícito y la dejaba vacía).
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_reorder_list_daily // CREATE EVENT evt_generate_reorder_list_daily ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 03:00:00' DO BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
DELETE FROM reorden_inventario;
INSERT INTO reorden_inventario (
        id_producto,
        sku,
        nombre_producto,
        stock_actual,
        umbral_minimo,
        cantidad_a_pedir
    )
SELECT id_producto,
    sku,
    nombre,
    stock,
    umbral_minimo,
    (umbral_minimo * 2) - stock
FROM productos
WHERE stock <= umbral_minimo
    AND activo = TRUE;
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 7. evt_rebuild_indexes_weekly
-- Optimiza las tablas más consultadas semanalmente para desfragmentar índices.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly // CREATE EVENT evt_rebuild_indexes_weekly ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-04 04:00:00' DO BEGIN OPTIMIZE TABLE ventas,
detalle_ventas,
productos,
clientes;
END // -- -----------------------------------------------------------------------------
-- 8. evt_suspend_inactive_accounts_quarterly
-- Desactiva cuentas de clientes sin compras ni actividad en más de 1 año.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly // CREATE EVENT evt_suspend_inactive_accounts_quarterly ON SCHEDULE EVERY 3 MONTH STARTS '2026-01-01 04:30:00' DO BEGIN
UPDATE clientes c
SET c.activo = FALSE
WHERE c.activo = TRUE
    AND (
        c.fecha_ultimo_pedido IS NULL
        OR c.fecha_ultimo_pedido < DATE_SUB(NOW(), INTERVAL 1 YEAR)
    )
    AND c.fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR);
END // -- -----------------------------------------------------------------------------
-- 9. evt_aggregate_daily_sales_data
-- Agrega las ventas del día anterior en resumen_ventas_diarias.
-- Los ingresos y pedidos salen de ventas SIN unir con detalle_ventas (si no, una
-- venta de 3 líneas se sumaba 3 veces); las unidades van en subconsulta aparte.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data // CREATE EVENT evt_aggregate_daily_sales_data ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 00:30:00' DO BEGIN
DECLARE v_fecha_ayer DATE;
SET v_fecha_ayer = DATE_SUB(CURDATE(), INTERVAL 1 DAY);
INSERT INTO resumen_ventas_diarias (
        fecha,
        total_ventas,
        total_pedidos,
        productos_vendidos
    )
SELECT v_fecha_ayer,
    COALESCE(SUM(v.total), 0.00),
    COUNT(*),
    COALESCE(
        (
            SELECT SUM(d.cantidad)
            FROM detalle_ventas d
                INNER JOIN ventas v2 ON d.id_venta = v2.id_venta
            WHERE v2.fecha_venta >= v_fecha_ayer
                AND v2.fecha_venta < CURDATE()
                AND v2.estado <> 'Cancelado'
        ),
        0
    )
FROM ventas v
WHERE v.fecha_venta >= v_fecha_ayer
    AND v.fecha_venta < CURDATE()
    AND v.estado <> 'Cancelado' ON DUPLICATE KEY
UPDATE total_ventas =
VALUES(total_ventas),
    total_pedidos =
VALUES(total_pedidos),
    productos_vendidos =
VALUES(productos_vendidos);
END // -- -----------------------------------------------------------------------------
-- 10. evt_check_data_consistency_nightly
-- Busca anomalías en los datos (ventas sin detalles o totales divergentes).
-- Solo inserta casos que aún no estén registrados (sin filas repetidas cada noche).
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_check_data_consistency_nightly // CREATE EVENT evt_check_data_consistency_nightly ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 03:30:00' DO BEGIN -- Detectar ventas sin líneas de detalle
INSERT INTO log_inconsistencias_datos (tipo, descripcion)
SELECT 'VENTA_SIN_DETALLE',
    CONCAT(
        'La venta ID ',
        v.id_venta,
        ' no tiene registros en detalle_ventas.'
    )
FROM ventas v
WHERE NOT EXISTS (
        SELECT 1
        FROM detalle_ventas d
        WHERE d.id_venta = v.id_venta
    )
    AND NOT EXISTS (
        SELECT 1
        FROM log_inconsistencias_datos l
        WHERE l.tipo = 'VENTA_SIN_DETALLE'
            AND l.descripcion = CONCAT(
                'La venta ID ',
                v.id_venta,
                ' no tiene registros en detalle_ventas.'
            )
    );
-- Detectar discrepancias entre el total de la venta y la suma de sus detalles
INSERT INTO log_inconsistencias_datos (tipo, descripcion)
SELECT x.tipo,
    x.descripcion
FROM (
        SELECT 'TOTAL_DISCREPANTE' AS tipo,
            CONCAT(
                'Venta ID ',
                v.id_venta,
                ': total en cabecera = ',
                v.total,
                ', suma detalles = ',
                SUM(d.cantidad * d.precio_unitario_congelado)
            ) AS descripcion
        FROM ventas v
            INNER JOIN detalle_ventas d ON v.id_venta = d.id_venta
        GROUP BY v.id_venta,
            v.total
        HAVING ABS(
                v.total - SUM(d.cantidad * d.precio_unitario_congelado)
            ) > 0.01
    ) x
WHERE NOT EXISTS (
        SELECT 1
        FROM log_inconsistencias_datos l
        WHERE l.tipo = x.tipo
            AND l.descripcion = x.descripcion
    );
END // -- -----------------------------------------------------------------------------
-- 11. evt_send_birthday_greetings_daily
-- Genera cupones especiales del 15% a clientes que cumplen años el día de hoy.
-- No duplica el cupón si el evento corre más de una vez el mismo día.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily // CREATE EVENT evt_send_birthday_greetings_daily ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 06:00:00' DO BEGIN
INSERT INTO cupones_cumpleanos (
        id_cliente,
        codigo_cupon,
        descuento_pct,
        fecha_expiracion
    )
SELECT c.id_cliente,
    CONCAT('CUMPLE-', c.id_cliente, '-', YEAR(CURDATE())),
    15.00,
    DATE_ADD(CURDATE(), INTERVAL 30 DAY)
FROM clientes c
WHERE MONTH(c.fecha_nacimiento) = MONTH(CURDATE())
    AND DAY(c.fecha_nacimiento) = DAY(CURDATE())
    AND c.activo = TRUE
    AND NOT EXISTS (
        SELECT 1
        FROM cupones_cumpleanos cu
        WHERE cu.codigo_cupon = CONCAT('CUMPLE-', c.id_cliente, '-', YEAR(CURDATE()))
    );
END // -- -----------------------------------------------------------------------------
-- 12. evt_update_product_rankings_hourly
-- Actualiza la tabla ranking_productos con los 20 productos más vendidos.
-- Se agregó el alias ingresos_generados (faltaba y el ORDER BY fallaba) y se
-- cambió TRUNCATE por DELETE dentro de una transacción.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_update_product_rankings_hourly // CREATE EVENT evt_update_product_rankings_hourly ON SCHEDULE EVERY 1 HOUR DO BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
DELETE FROM ranking_productos;
INSERT INTO ranking_productos (
        id_producto,
        nombre_producto,
        posicion,
        unidades_vendidas,
        ingresos_generados
    )
SELECT p.id_producto,
    p.nombre,
    ROW_NUMBER() OVER (
        ORDER BY SUM(d.cantidad * d.precio_unitario_congelado) DESC
    ) AS pos,
    COALESCE(SUM(d.cantidad), 0) AS unidades_vendidas,
    COALESCE(
        SUM(d.cantidad * d.precio_unitario_congelado),
        0.00
    ) AS ingresos_generados
FROM productos p
    INNER JOIN detalle_ventas d ON p.id_producto = d.id_producto
    INNER JOIN ventas v ON d.id_venta = v.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto,
    p.nombre
ORDER BY ingresos_generados DESC
LIMIT 20;
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 13. evt_backup_critical_tables_daily
-- Realiza un snapshot lógico de las ventas más recientes cada noche.
-- Solo copia ventas que no estén ya respaldadas con el mismo total.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_backup_critical_tables_daily // CREATE EVENT evt_backup_critical_tables_daily ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 01:30:00' DO BEGIN
INSERT INTO backup_logico_ventas (id_venta, id_cliente, fecha_venta, total)
SELECT v.id_venta,
    v.id_cliente,
    v.fecha_venta,
    v.total
FROM ventas v
WHERE v.fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    AND NOT EXISTS (
        SELECT 1
        FROM backup_logico_ventas b
        WHERE b.id_venta = v.id_venta
            AND b.total = v.total
    );
END // -- -----------------------------------------------------------------------------
-- 14. evt_clear_abandoned_carts_daily
-- Vacía los carritos abandonados que lleven más de 72 horas sin confirmación.
-- Usa carritos + detalle_carrito (carrito_compras no existe).
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily // CREATE EVENT evt_clear_abandoned_carts_daily ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 04:00:00' DO BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
DELETE dc
FROM detalle_carrito dc
    INNER JOIN carritos ca ON dc.id_carrito = ca.id_carrito
WHERE ca.estado = 'Abandonado'
    AND ca.fecha_creacion < DATE_SUB(NOW(), INTERVAL 72 HOUR);
DELETE FROM carritos
WHERE estado = 'Abandonado'
    AND fecha_creacion < DATE_SUB(NOW(), INTERVAL 72 HOUR);
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 15. evt_calculate_monthly_kpis
-- Calcula y consolida los KPIs del mes anterior.
-- Ingresos, ticket y pedidos salen de ventas SIN join a detalles; el margen va en
-- una subconsulta aparte. No inserta dos veces el mismo año/mes.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_calculate_monthly_kpis // CREATE EVENT evt_calculate_monthly_kpis ON SCHEDULE EVERY 1 MONTH STARTS '2026-01-01 05:00:00' DO BEGIN
DECLARE v_anio INT;
DECLARE v_mes INT;
DECLARE v_inicio DATE;
DECLARE v_fin DATE;
SET v_anio = YEAR(DATE_SUB(NOW(), INTERVAL 1 MONTH));
SET v_mes = MONTH(DATE_SUB(NOW(), INTERVAL 1 MONTH));
SET v_inicio = STR_TO_DATE(CONCAT(v_anio, '-', v_mes, '-01'), '%Y-%m-%d');
SET v_fin = DATE_ADD(v_inicio, INTERVAL 1 MONTH);
INSERT INTO kpis_mensuales (
        anio,
        mes,
        ingresos_totales,
        margen_bruto,
        ticket_promedio,
        total_clientes_activos,
        pedidos_completados
    )
SELECT v_anio,
    v_mes,
    t.ingresos_totales,
    m.margen_bruto,
    t.ticket_promedio,
    t.clientes_activos,
    t.pedidos
FROM (
        SELECT COALESCE(SUM(v.total), 0.00) AS ingresos_totales,
            COALESCE(ROUND(AVG(v.total), 2), 0.00) AS ticket_promedio,
            COUNT(DISTINCT v.id_cliente) AS clientes_activos,
            COUNT(*) AS pedidos
        FROM ventas v
        WHERE v.fecha_venta >= v_inicio
            AND v.fecha_venta < v_fin
            AND v.estado <> 'Cancelado'
    ) t
    CROSS JOIN (
        SELECT COALESCE(
                SUM(
                    d.cantidad * (d.precio_unitario_congelado - p.costo)
                ),
                0.00
            ) AS margen_bruto
        FROM ventas v
            INNER JOIN detalle_ventas d ON v.id_venta = d.id_venta
            INNER JOIN productos p ON d.id_producto = p.id_producto
        WHERE v.fecha_venta >= v_inicio
            AND v.fecha_venta < v_fin
            AND v.estado <> 'Cancelado'
    ) m
WHERE NOT EXISTS (
        SELECT 1
        FROM kpis_mensuales k
        WHERE k.anio = v_anio
            AND k.mes = v_mes
    );
END // -- -----------------------------------------------------------------------------
-- 16. evt_refresh_materialized_views_nightly
-- Refresca vm_resumen_categoria con las estadísticas actualizadas.
-- Los cancelados se excluyen con un INNER JOIN anidado (antes el filtro en un
-- LEFT JOIN no quitaba las líneas de detalle). DELETE en transacción en vez de
-- TRUNCATE.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly // CREATE EVENT evt_refresh_materialized_views_nightly ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 02:45:00' DO BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
DELETE FROM vm_resumen_categoria;
INSERT INTO vm_resumen_categoria (
        id_categoria,
        nombre_categoria,
        total_productos,
        unidades_vendidas,
        ingresos_acumulados,
        ultima_actualizacion
    )
SELECT c.id_categoria,
    c.nombre,
    COUNT(DISTINCT p.id_producto),
    COALESCE(SUM(d.cantidad), 0),
    COALESCE(
        SUM(d.cantidad * d.precio_unitario_congelado),
        0.00
    ),
    NOW()
FROM categorias c
    LEFT JOIN productos p ON c.id_categoria = p.id_categoria
    LEFT JOIN (
        detalle_ventas d
        INNER JOIN ventas v ON d.id_venta = v.id_venta
        AND v.estado <> 'Cancelado'
    ) ON p.id_producto = d.id_producto
GROUP BY c.id_categoria,
    c.nombre;
COMMIT;
END // -- -----------------------------------------------------------------------------
-- 17. evt_log_database_size_weekly
-- Registra el volumen total ocupado por los datos e índices en MB.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_log_database_size_weekly // CREATE EVENT evt_log_database_size_weekly ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-04 05:30:00' DO BEGIN
INSERT INTO log_tamano_bd (tamano_mb, total_tablas)
SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2),
    COUNT(*)
FROM information_schema.tables
WHERE table_schema = 'ecommerce_db';
END // -- -----------------------------------------------------------------------------
-- 18. evt_detect_fraudulent_activity_hourly
-- Identifica clientes con 3 o más ventas canceladas o pendientes en la última hora.
-- No vuelve a alertar por las mismas ventas: se omite al cliente si ya existe una
-- alerta posterior a su primera venta sospechosa de la ventana.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly // CREATE EVENT evt_detect_fraudulent_activity_hourly ON SCHEDULE EVERY 1 HOUR DO BEGIN
INSERT INTO alertas_fraude (id_cliente, motivo, cantidad_intentos)
SELECT x.id_cliente,
    'Múltiples transacciones fallidas o canceladas en corto lapso',
    x.intentos
FROM (
        SELECT v.id_cliente,
            COUNT(*) AS intentos,
            MIN(v.fecha_venta) AS primera_venta
        FROM ventas v
        WHERE v.estado IN ('Cancelado', 'Pendiente de Pago')
            AND v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
        GROUP BY v.id_cliente
        HAVING COUNT(*) >= 3
    ) x
WHERE NOT EXISTS (
        SELECT 1
        FROM alertas_fraude a
        WHERE a.id_cliente = x.id_cliente
            AND a.fecha_deteccion >= x.primera_venta
    );
END // -- -----------------------------------------------------------------------------
-- 19. evt_generate_supplier_performance_report_monthly
-- Genera el reporte mensual de rendimiento comercial para cada proveedor.
-- No duplica proveedor/año/mes.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly // CREATE EVENT evt_generate_supplier_performance_report_monthly ON SCHEDULE EVERY 1 MONTH STARTS '2026-01-01 05:15:00' DO BEGIN
DECLARE v_anio INT;
DECLARE v_mes INT;
DECLARE v_inicio DATE;
DECLARE v_fin DATE;
SET v_anio = YEAR(DATE_SUB(NOW(), INTERVAL 1 MONTH));
SET v_mes = MONTH(DATE_SUB(NOW(), INTERVAL 1 MONTH));
SET v_inicio = STR_TO_DATE(CONCAT(v_anio, '-', v_mes, '-01'), '%Y-%m-%d');
SET v_fin = DATE_ADD(v_inicio, INTERVAL 1 MONTH);
INSERT INTO reporte_rendimiento_proveedores (
        id_proveedor,
        nombre_proveedor,
        anio,
        mes,
        unidades_vendidas,
        total_facturado
    )
SELECT pr.id_proveedor,
    pr.nombre,
    v_anio,
    v_mes,
    COALESCE(SUM(d.cantidad), 0),
    COALESCE(
        SUM(d.cantidad * d.precio_unitario_congelado),
        0.00
    )
FROM proveedores pr
    INNER JOIN productos p ON pr.id_proveedor = p.id_proveedor
    INNER JOIN detalle_ventas d ON p.id_producto = d.id_producto
    INNER JOIN ventas v ON d.id_venta = v.id_venta
WHERE v.fecha_venta >= v_inicio
    AND v.fecha_venta < v_fin
    AND v.estado <> 'Cancelado'
    AND NOT EXISTS (
        SELECT 1
        FROM reporte_rendimiento_proveedores r
        WHERE r.id_proveedor = pr.id_proveedor
            AND r.anio = v_anio
            AND r.mes = v_mes
    )
GROUP BY pr.id_proveedor,
    pr.nombre;
END // -- -----------------------------------------------------------------------------
-- 20. evt_purge_soft_deleted_records_weekly
-- Elimina permanentemente registros marcados como inactivos hace más de 30 días.
-- Carritos: se purgan los ya cerrados (ni 'Activo' ni 'Abandonado') de más de
-- 30 días; AJUSTA esa condición a los valores reales de carritos.estado en 01.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly // CREATE EVENT evt_purge_soft_deleted_records_weekly ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-04 03:00:00' DO BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
RESIGNAL;
END;
START TRANSACTION;
-- Purga permanente de carritos ya cerrados de más de 30 días
DELETE dc
FROM detalle_carrito dc
    INNER JOIN carritos ca ON dc.id_carrito = ca.id_carrito
WHERE ca.estado NOT IN ('Activo', 'Abandonado')
    AND ca.fecha_creacion < DATE_SUB(NOW(), INTERVAL 30 DAY);
DELETE FROM carritos
WHERE estado NOT IN ('Activo', 'Abandonado')
    AND fecha_creacion < DATE_SUB(NOW(), INTERVAL 30 DAY);
-- Purga de promociones inactivas de más de 90 días
DELETE FROM promociones
WHERE activo = FALSE
    AND fecha_fin < DATE_SUB(NOW(), INTERVAL 90 DAY);
COMMIT;
END // DELIMITER;