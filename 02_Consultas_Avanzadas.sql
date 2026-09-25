-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: 02_Consultas_Avanzadas.sql
-- DESCRIPCIÓN: 20 Consultas de análisis y reporteo analítico sobre el negocio.
-- MOTOR: MySQL 8.0+
-- =============================================================================

USE ecommerce_db;

-- -----------------------------------------------------------------------------
-- 1. Top 10 Productos Más Vendidos:
-- Generar un ranking con los 10 productos que han generado más ingresos.
-- -----------------------------------------------------------------------------
SELECT 
    DENSE_RANK() OVER (ORDER BY SUM(d.cantidad * d.precio_unitario_congelado) DESC) AS ranking,
    p.id_producto,
    p.sku,
    p.nombre AS producto,
    c.nombre AS categoria,
    SUM(d.cantidad) AS unidades_vendidas,
    SUM(d.cantidad * d.precio_unitario_congelado) AS total_ingresos
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
INNER JOIN detalle_ventas d ON p.id_producto = d.id_producto
INNER JOIN ventas v ON d.id_venta = v.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.sku, p.nombre, c.nombre
ORDER BY total_ingresos DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- 2. Productos con Bajas Ventas:
-- Identificar los productos en el 10% inferior de ventas para considerar su descontinuación.
-- -----------------------------------------------------------------------------
WITH VentasPorProducto AS (
    SELECT 
        p.id_producto,
        p.sku,
        p.nombre,
        c.nombre AS categoria,
        p.stock,
        p.precio,
        COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0.00) AS total_ventas,
        NTILE(10) OVER (ORDER BY COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0.00) ASC) AS decil_ventas
    FROM productos p
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
    LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
    LEFT JOIN ventas v ON d.id_venta = v.id_venta AND v.estado <> 'Cancelado'
    GROUP BY p.id_producto, p.sku, p.nombre, c.nombre, p.stock, p.precio
)
SELECT 
    id_producto,
    sku,
    nombre AS producto,
    categoria,
    stock,
    precio,
    total_ventas,
    'Candidato a Descontinuación (Decil 1 - 10% Inferior)' AS recomendacion
FROM VentasPorProducto
WHERE decil_ventas = 1
ORDER BY total_ventas ASC;


-- -----------------------------------------------------------------------------
-- 3. Clientes VIP:
-- Listar los 5 clientes con el mayor valor de vida (LTV), basado en su gasto total histórico.
-- -----------------------------------------------------------------------------
SELECT 
    DENSE_RANK() OVER (ORDER BY SUM(v.total) DESC) AS ranking_vip,
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    c.email,
    c.ciudad,
    c.nivel_lealtad,
    COUNT(v.id_venta) AS total_pedidos_completados,
    ROUND(AVG(v.total), 2) AS ticket_promedio,
    SUM(v.total) AS ltv_historico
FROM clientes c
INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido, c.email, c.ciudad, c.nivel_lealtad
ORDER BY ltv_historico DESC
LIMIT 5;


-- -----------------------------------------------------------------------------
-- 4. Análisis de Ventas Mensuales:
-- Mostrar las ventas totales agrupadas por mes y año.
-- -----------------------------------------------------------------------------
SELECT 
    YEAR(v.fecha_venta) AS anio,
    MONTH(v.fecha_venta) AS mes_numero,
    DATE_FORMAT(v.fecha_venta, '%Y-%M') AS periodo,
    COUNT(DISTINCT v.id_venta) AS total_pedidos,
    SUM(v.total) AS ventas_totales,
    ROUND(AVG(v.total), 2) AS ticket_promedio,
    COALESCE(
        ROUND(
            ((SUM(v.total) - LAG(SUM(v.total)) OVER (ORDER BY YEAR(v.fecha_venta), MONTH(v.fecha_venta))) 
            / NULLIF(LAG(SUM(v.total)) OVER (ORDER BY YEAR(v.fecha_venta), MONTH(v.fecha_venta)), 0)) * 100, 
        2), 
    0.00) AS crecimiento_porcentual_mom
FROM ventas v
WHERE v.estado <> 'Cancelado'
GROUP BY YEAR(v.fecha_venta), MONTH(v.fecha_venta), DATE_FORMAT(v.fecha_venta, '%Y-%M')
ORDER BY anio ASC, mes_numero ASC;


-- -----------------------------------------------------------------------------
-- 5. Crecimiento de Clientes:
-- Calcular el número de nuevos clientes registrados por trimestre.
-- -----------------------------------------------------------------------------
SELECT 
    anio,
    trimestre,
    CONCAT(anio, '-Q', trimestre) AS periodo_trimestre,
    nuevos_clientes_registrados,
    SUM(nuevos_clientes_registrados) OVER (ORDER BY anio, trimestre) AS clientes_acumulados
FROM (
    SELECT 
        YEAR(c.fecha_registro) AS anio,
        QUARTER(c.fecha_registro) AS trimestre,
        COUNT(c.id_cliente) AS nuevos_clientes_registrados
    FROM clientes c
    GROUP BY YEAR(c.fecha_registro), QUARTER(c.fecha_registro)
) AS clientes_por_trimestre
ORDER BY anio ASC, trimestre ASC;


-- -----------------------------------------------------------------------------
-- 6. Tasa de Compra Repetida:
-- Determinar qué porcentaje de clientes ha realizado más de una compra.
-- -----------------------------------------------------------------------------
WITH ConteoComprasPorCliente AS (
    SELECT 
        c.id_cliente,
        COUNT(v.id_venta) AS total_compras
    FROM clientes c
    LEFT JOIN ventas v ON c.id_cliente = v.id_cliente AND v.estado <> 'Cancelado'
    GROUP BY c.id_cliente
)
SELECT 
    COUNT(CASE WHEN total_compras >= 1 THEN 1 END) AS clientes_con_compras,
    COUNT(CASE WHEN total_compras > 1 THEN 1 END) AS clientes_recurrentes,
    COUNT(CASE WHEN total_compras = 1 THEN 1 END) AS clientes_compra_unica,
    ROUND(
        (COUNT(CASE WHEN total_compras > 1 THEN 1 END) * 100.0) 
        / NULLIF(COUNT(CASE WHEN total_compras >= 1 THEN 1 END), 0), 
    2) AS tasa_compra_repetida_pct
FROM ConteoComprasPorCliente;


-- -----------------------------------------------------------------------------
-- 7. Productos Comprados Juntos Frecuentemente:
-- Identificar pares de productos que a menudo se compran en la misma transacción.
-- -----------------------------------------------------------------------------
SELECT 
    p1.nombre AS producto_a,
    p2.nombre AS producto_b,
    COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas d1
INNER JOIN detalle_ventas d2 
    ON d1.id_venta = d2.id_venta AND d1.id_producto < d2.id_producto
INNER JOIN productos p1 ON d1.id_producto = p1.id_producto
INNER JOIN productos p2 ON d2.id_producto = p2.id_producto
INNER JOIN ventas v ON d1.id_venta = v.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p1.nombre, p2.nombre
ORDER BY veces_comprados_juntos DESC, producto_a ASC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- 8. Rotación de Inventario:
-- Calcular la tasa de rotación de stock para cada categoría de producto.
-- (Rotación = Costo Total de Bienes Vendidos [COGS] / Valor del Inventario Actual)
-- -----------------------------------------------------------------------------
SELECT 
    c.id_categoria,
    c.nombre AS categoria,
    COALESCE(SUM(d.cantidad * p.costo), 0.00) AS costo_mercancia_vendida_cogs,
    SUM(p.stock * p.costo) AS valor_inventario_actual,
    COALESCE(
        ROUND(
            SUM(d.cantidad * p.costo) / NULLIF(SUM(p.stock * p.costo), 0), 
        3), 
    0.000) AS indice_rotacion_inventario
FROM categorias c
INNER JOIN productos p ON c.id_categoria = p.id_categoria
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
LEFT JOIN ventas v ON d.id_venta = v.id_venta AND v.estado <> 'Cancelado'
GROUP BY c.id_categoria, c.nombre
ORDER BY indice_rotacion_inventario DESC;


-- -----------------------------------------------------------------------------
-- 9. Productos que Necesitan Reabastecimiento:
-- Listar productos cuyo stock actual está por debajo de su umbral mínimo.
-- -----------------------------------------------------------------------------
SELECT 
    p.id_producto,
    p.sku,
    p.nombre AS producto,
    c.nombre AS categoria,
    prov.nombre AS proveedor,
    prov.email_contacto AS email_proveedor,
    p.stock AS stock_actual,
    p.umbral_minimo,
    (p.umbral_minimo - p.stock) AS unidades_deficit,
    ROUND((p.umbral_minimo * 2) - p.stock, 0) AS reabastecimiento_sugerido
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
INNER JOIN proveedores prov ON p.id_proveedor = prov.id_proveedor
WHERE p.stock <= p.umbral_minimo AND p.activo = TRUE
ORDER BY (p.umbral_minimo - p.stock) DESC, p.stock ASC;


-- -----------------------------------------------------------------------------
-- 10. Análisis de Carrito Abandonado (Simulado):
-- Identificar clientes que agregaron productos pero no completaron una venta en un período determinado.
-- -----------------------------------------------------------------------------
SELECT 
    cb.id_carrito,
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    c.email,
    p.nombre AS producto_abandonado,
    cb.cantidad,
    p.precio,
    (cb.cantidad * p.precio) AS valor_carrito,
    cb.fecha_creacion AS fecha_abandono,
    TIMESTAMPDIFF(HOUR, cb.fecha_creacion, NOW()) AS horas_abandonado
FROM carrito_compras cb
INNER JOIN clientes c ON cb.id_cliente = c.id_cliente
INNER JOIN productos p ON cb.id_producto = p.id_producto
WHERE cb.recuperado = FALSE
  AND cb.fecha_creacion < DATE_SUB(NOW(), INTERVAL 24 HOUR)
ORDER BY cb.fecha_creacion DESC;


-- -----------------------------------------------------------------------------
-- 11. Rendimiento de Proveedores:
-- Clasificar a los proveedores según el volumen de ventas de sus productos.
-- -----------------------------------------------------------------------------
SELECT 
    DENSE_RANK() OVER (ORDER BY COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0) DESC) AS ranking,
    pr.id_proveedor,
    pr.nombre AS proveedor,
    pr.email_contacto,
    COUNT(DISTINCT p.id_producto) AS catalogo_productos_suministrados,
    COALESCE(SUM(d.cantidad), 0) AS unidades_totales_vendidas,
    COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0.00) AS ingresos_totales_generados,
    COALESCE(SUM(d.cantidad * (d.precio_unitario_congelado - p.costo)), 0.00) AS margen_bruto_generado
FROM proveedores pr
LEFT JOIN productos p ON pr.id_proveedor = p.id_proveedor
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
LEFT JOIN ventas v ON d.id_venta = v.id_venta AND v.estado <> 'Cancelado'
GROUP BY pr.id_proveedor, pr.nombre, pr.email_contacto
ORDER BY ingresos_totales_generados DESC;


-- -----------------------------------------------------------------------------
-- 12. Análisis Geográfico de Ventas:
-- Agrupar las ventas por ciudad o región del cliente.
-- -----------------------------------------------------------------------------
SELECT 
    c.pais,
    c.ciudad,
    COUNT(DISTINCT c.id_cliente) AS clientes_totales,
    COUNT(DISTINCT v.id_venta) AS total_pedidos,
    SUM(v.total) AS ventas_totales,
    ROUND(SUM(v.total) / COUNT(DISTINCT v.id_venta), 2) AS ticket_promedio_ciudad,
    ROUND((SUM(v.total) / (SELECT SUM(total) FROM ventas WHERE estado <> 'Cancelado')) * 100, 2) AS cuota_porcentual_ventas
FROM clientes c
INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.pais, c.ciudad
ORDER BY ventas_totales DESC;


-- -----------------------------------------------------------------------------
-- 13. Ventas por Hora del Día:
-- Determinar las horas pico de compras para optimizar campañas de marketing.
-- -----------------------------------------------------------------------------
SELECT 
    hora_del_dia,
    CONCAT(LPAD(hora_del_dia, 2, '0'), ':00 - ', LPAD(hora_del_dia + 1, 2, '0'), ':00') AS franja_horaria,
    cantidad_transacciones,
    total_facturado,
    promedio_por_transaccion,
    CASE 
        WHEN cantidad_transacciones >= 4 THEN 'Franja Pico Alta'
        WHEN cantidad_transacciones BETWEEN 2 AND 3 THEN 'Franja Media'
        ELSE 'Franja Baja'
    END AS clasificacion_trafico
FROM (
    SELECT 
        HOUR(v.fecha_venta) AS hora_del_dia,
        COUNT(v.id_venta) AS cantidad_transacciones,
        SUM(v.total) AS total_facturado,
        ROUND(AVG(v.total), 2) AS promedio_por_transaccion
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
    GROUP BY HOUR(v.fecha_venta)
) AS ventas_por_hora
ORDER BY cantidad_transacciones DESC, total_facturado DESC;


-- -----------------------------------------------------------------------------
-- 14. Impacto de Promociones:
-- Comparar las ventas de un producto antes, durante y después de una campaña de descuento.
-- Caso de estudio: Campaña 'TECHWEEK2025' (2025-02-10 al 2025-02-17) sobre Laptop UltraBook (ID 1)
-- -----------------------------------------------------------------------------
SELECT 
    p.nombre AS producto,
    'TECHWEEK2025 (2025-02-10 al 2025-02-17)' AS promocion_evaluada,
    SUM(CASE 
        WHEN v.fecha_venta BETWEEN '2025-02-01 00:00:00' AND '2025-02-09 23:59:59' 
        THEN d.cantidad ELSE 0 
    END) AS unidades_antes_promo,
    SUM(CASE 
        WHEN v.fecha_venta BETWEEN '2025-02-10 00:00:00' AND '2025-02-17 23:59:59' 
        THEN d.cantidad ELSE 0 
    END) AS unidades_durante_promo,
    SUM(CASE 
        WHEN v.fecha_venta BETWEEN '2025-02-18 00:00:00' AND '2025-02-28 23:59:59' 
        THEN d.cantidad ELSE 0 
    END) AS unidades_despues_promo,
    SUM(CASE 
        WHEN v.fecha_venta BETWEEN '2025-02-10 00:00:00' AND '2025-02-17 23:59:59' 
        THEN d.cantidad * d.precio_unitario_congelado ELSE 0 
    END) AS facturacion_durante_promo
FROM productos p
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
LEFT JOIN ventas v ON d.id_venta = v.id_venta AND v.estado <> 'Cancelado'
WHERE p.id_producto = 1
GROUP BY p.nombre;


-- -----------------------------------------------------------------------------
-- 15. Análisis de Cohort:
-- Analizar la retención de clientes mes a mes desde su primera compra.
-- -----------------------------------------------------------------------------
WITH PrimeraCompraCliente AS (
    SELECT 
        v.id_cliente,
        DATE_FORMAT(MIN(v.fecha_venta), '%Y-%m-01') AS cohorte_inicial
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
    GROUP BY v.id_cliente
),
ActividadClientes AS (
    SELECT 
        v.id_cliente,
        DATE_FORMAT(v.fecha_venta, '%Y-%m-01') AS mes_actividad,
        TIMESTAMPDIFF(MONTH, STR_TO_DATE(p.cohorte_inicial, '%Y-%m-%d'), STR_TO_DATE(DATE_FORMAT(v.fecha_venta, '%Y-%m-01'), '%Y-%m-%d')) AS meses_transcurridos
    FROM ventas v
    INNER JOIN PrimeraCompraCliente p ON v.id_cliente = p.id_cliente
    WHERE v.estado <> 'Cancelado'
    GROUP BY v.id_cliente, DATE_FORMAT(v.fecha_venta, '%Y-%m-01'), meses_transcurridos
)
SELECT 
    p.cohorte_inicial AS cohorte_primer_mes,
    COUNT(DISTINCT p.id_cliente) AS tamano_cohorte,
    COUNT(DISTINCT CASE WHEN a.meses_transcurridos = 0 THEN a.id_cliente END) AS mes_0,
    COUNT(DISTINCT CASE WHEN a.meses_transcurridos = 1 THEN a.id_cliente END) AS mes_1,
    COUNT(DISTINCT CASE WHEN a.meses_transcurridos = 2 THEN a.id_cliente END) AS mes_2,
    COUNT(DISTINCT CASE WHEN a.meses_transcurridos = 3 THEN a.id_cliente END) AS mes_3,
    ROUND((COUNT(DISTINCT CASE WHEN a.meses_transcurridos = 1 THEN a.id_cliente END) * 100.0) 
          / COUNT(DISTINCT p.id_cliente), 2) AS tasa_retencion_mes1_pct
FROM PrimeraCompraCliente p
LEFT JOIN ActividadClientes a ON p.id_cliente = a.id_cliente
GROUP BY p.cohorte_inicial
ORDER BY p.cohorte_inicial ASC;


-- -----------------------------------------------------------------------------
-- 16. Margen de Beneficio por Producto:
-- Calcular el margen de beneficio para cada producto (precio vs costo).
-- -----------------------------------------------------------------------------
SELECT 
    p.id_producto,
    p.sku,
    p.nombre AS producto,
    c.nombre AS categoria,
    p.costo,
    p.precio,
    (p.precio - p.costo) AS margen_bruto_unitario,
    ROUND(((p.precio - p.costo) / p.precio) * 100, 2) AS margen_rentabilidad_pct,
    COALESCE(SUM(d.cantidad), 0) AS unidades_vendidas_historicas,
    COALESCE(SUM(d.cantidad * (d.precio_unitario_congelado - p.costo)), 0.00) AS beneficio_total_acumulado
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
LEFT JOIN ventas v ON d.id_venta = v.id_venta AND v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.sku, p.nombre, c.nombre, p.costo, p.precio
ORDER BY beneficio_total_acumulado DESC, margen_rentabilidad_pct DESC;


-- -----------------------------------------------------------------------------
-- 17. Tiempo Promedio Entre Compras:
-- Calcular el tiempo medio que tarda un cliente en volver a comprar.
-- -----------------------------------------------------------------------------
WITH FechasVentasConsecutivas AS (
    SELECT 
        v.id_cliente,
        v.id_venta,
        v.fecha_venta,
        LAG(v.fecha_venta) OVER (PARTITION BY v.id_cliente ORDER BY v.fecha_venta ASC) AS fecha_compra_anterior
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
),
IntervalosPorCliente AS (
    SELECT 
        id_cliente,
        DATEDIFF(fecha_venta, fecha_compra_anterior) AS dias_entre_compras
    FROM FechasVentasConsecutivas
    WHERE fecha_compra_anterior IS NOT NULL
)
SELECT 
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    COUNT(i.dias_entre_compras) AS cantidad_recompras,
    ROUND(AVG(i.dias_entre_compras), 1) AS dias_promedio_entre_compras,
    MIN(i.dias_entre_compras) AS recompra_mas_rapida_dias,
    MAX(i.dias_entre_compras) AS recompra_mas_lenta_dias
FROM clientes c
INNER JOIN IntervalosPorCliente i ON c.id_cliente = i.id_cliente
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY dias_promedio_entre_compras ASC;


-- -----------------------------------------------------------------------------
-- 18. Productos Más Vistos vs. Comprados:
-- Comparar los productos más visitados con los más comprados (Tasa de Conversión).
-- -----------------------------------------------------------------------------
SELECT 
    p.id_producto,
    p.sku,
    p.nombre AS producto,
    c.nombre AS categoria,
    p.vistas AS visitas_totales,
    COALESCE(SUM(d.cantidad), 0) AS unidades_compradas,
    ROUND(
        (COALESCE(SUM(d.cantidad), 0) / NULLIF(p.vistas, 0)) * 100, 
    2) AS tasa_conversion_visita_a_compra_pct
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
LEFT JOIN ventas v ON d.id_venta = v.id_venta AND v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.sku, p.nombre, c.nombre, p.vistas
ORDER BY tasa_conversion_visita_a_compra_pct DESC, visitas_totales DESC;


-- -----------------------------------------------------------------------------
-- 19. Segmentación de Clientes (RFM):
-- Clasificar a los clientes en segmentos (Recencia, Frecuencia, Monetario).
-- -----------------------------------------------------------------------------
WITH MetricasRFM AS (
    SELECT 
        c.id_cliente,
        CONCAT(c.nombre, ' ', c.apellido) AS cliente,
        c.email,
        DATEDIFF(CURRENT_DATE, MAX(v.fecha_venta)) AS recencia_dias,
        COUNT(DISTINCT v.id_venta) AS frecuencia_pedidos,
        SUM(v.total) AS valor_monetario
    FROM clientes c
    INNER JOIN ventas v ON c.id_cliente = v.id_cliente
    WHERE v.estado <> 'Cancelado'
    GROUP BY c.id_cliente, c.nombre, c.apellido, c.email
),
PuntuacionRFM AS (
    SELECT 
        id_cliente,
        cliente,
        email,
        recencia_dias,
        frecuencia_pedidos,
        valor_monetario,
        NTILE(4) OVER (ORDER BY recencia_dias DESC) AS score_r,
        NTILE(4) OVER (ORDER BY frecuencia_pedidos ASC) AS score_f,
        NTILE(4) OVER (ORDER BY valor_monetario ASC) AS score_m
    FROM MetricasRFM
)
SELECT 
    id_cliente,
    cliente,
    email,
    recencia_dias,
    frecuencia_pedidos,
    valor_monetario,
    CONCAT(score_r, score_f, score_m) AS rfm_cell,
    CASE 
        WHEN score_r >= 3 AND score_f >= 3 AND score_m >= 3 THEN 'Clientes VIP / Campeones'
        WHEN score_r >= 3 AND score_f >= 2 THEN 'Clientes Fieles y Activos'
        WHEN score_r >= 3 AND score_f = 1 THEN 'Nuevos Clientes Prometedores'
        WHEN score_r <= 2 AND score_f >= 3 THEN 'Clientes en Riesgo de Abandono'
        ELSE 'Clientes Inactivos / Hibernando'
    END AS segmento_cliente
FROM PuntuacionRFM
ORDER BY valor_monetario DESC;


-- -----------------------------------------------------------------------------
-- 20. Predicción de Demanda Simple:
-- Utilizar datos de ventas pasadas para proyectar las ventas del próximo mes
-- para una categoría específica (ej. 'Electrónica', ID = 1).
-- -----------------------------------------------------------------------------
WITH VentasMensualesCategoria AS (
    SELECT 
        c.nombre AS categoria,
        YEAR(v.fecha_venta) AS anio,
        MONTH(v.fecha_venta) AS mes,
        SUM(d.cantidad) AS unidades_vendidas_mes,
        SUM(d.cantidad * d.precio_unitario_congelado) AS ingresos_mes
    FROM detalle_ventas d
    INNER JOIN productos p ON d.id_producto = p.id_producto
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
    INNER JOIN ventas v ON d.id_venta = v.id_venta
    WHERE c.id_categoria = 1 AND v.estado <> 'Cancelado'
    GROUP BY c.nombre, YEAR(v.fecha_venta), MONTH(v.fecha_venta)
)
SELECT 
    categoria,
    ROUND(AVG(unidades_vendidas_mes), 0) AS demanda_promedio_mensual_unidades,
    ROUND(AVG(ingresos_mes), 2) AS facturacion_promedio_mensual_estimada,
    -- Proyección simple usando promedio ponderado con tendencia reciente (+5%)
    ROUND(AVG(unidades_vendidas_mes) * 1.05, 0) AS proyeccion_demanda_proximo_mes_unidades,
    ROUND(AVG(ingresos_mes) * 1.05, 2) AS proyeccion_ingresos_proximo_mes
FROM VentasMensualesCategoria
GROUP BY categoria;