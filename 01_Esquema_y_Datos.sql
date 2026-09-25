-- ============================================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto: Base de Datos para un E-commerce
-- Contenido: Creación de la estructura completa (CREATE TABLE) y carga de
--            datos de ejemplo (INSERT INTO). Motor objetivo: MySQL 8.0+
-- ============================================================================

CREATE DATABASE IF NOT EXISTS ecommerce_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE ecommerce_db;

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- Limpieza (permite re-ejecutar el script sin errores)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS alertas_fraude;
DROP TABLE IF EXISTS alertas_stock;
DROP TABLE IF EXISTS resenas;
DROP TABLE IF EXISTS referidos;
DROP TABLE IF EXISTS producto_vistas;
DROP TABLE IF EXISTS detalle_carrito;
DROP TABLE IF EXISTS carritos;
DROP TABLE IF EXISTS promociones;
DROP TABLE IF EXISTS tasas_cambio;
DROP TABLE IF EXISTS auditoria_estado_pedido;
DROP TABLE IF EXISTS auditoria_clientes;
DROP TABLE IF EXISTS auditoria_login;
DROP TABLE IF EXISTS auditoria_permisos;
DROP TABLE IF EXISTS ventas_archivadas;
DROP TABLE IF EXISTS kpis_mensuales;
DROP TABLE IF EXISTS tamano_bd_historico;
DROP TABLE IF EXISTS reporte_rendimiento_proveedores;
DROP TABLE IF EXISTS detalle_ventas;
DROP TABLE IF EXISTS ventas;
DROP TABLE IF EXISTS productos;
DROP TABLE IF EXISTS proveedores;
DROP TABLE IF EXISTS categorias;
DROP TABLE IF EXISTS clientes;
-- Las tablas log_cambios_precio y reporte_ventas_semanales se crean en
-- 05_Triggers.sql y 06_Eventos.sql respectivamente, tal como lo pide el
-- enunciado del proyecto.
DROP TABLE IF EXISTS log_cambios_precio;
DROP TABLE IF EXISTS reporte_ventas_semanales;

-- ----------------------------------------------------------------------------
-- Entidad: Categorías
-- ----------------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria     INT AUTO_INCREMENT PRIMARY KEY,
    nombre           VARCHAR(100) NOT NULL UNIQUE,
    descripcion      TEXT NULL,
    total_productos  INT NOT NULL DEFAULT 0
);

-- ----------------------------------------------------------------------------
-- Entidad: Proveedores
-- ----------------------------------------------------------------------------
CREATE TABLE proveedores (
    id_proveedor      INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(150) NOT NULL,
    email_contacto    VARCHAR(150) UNIQUE,
    telefono_contacto VARCHAR(30)
);

-- ----------------------------------------------------------------------------
-- Entidad: Clientes
-- ----------------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente        INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(100) NOT NULL,
    apellido          VARCHAR(100) NOT NULL,
    email             VARCHAR(150) NOT NULL UNIQUE,
    contrasena_hash   VARCHAR(255) NOT NULL,
    direccion_envio   VARCHAR(255),
    ciudad            VARCHAR(100),
    fecha_nacimiento  DATE NULL,
    id_sucursal       INT NULL,
    fecha_registro    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_gastado     DECIMAL(12,2) NOT NULL DEFAULT 0,
    nivel_lealtad     ENUM('Bronce','Plata','Oro') NOT NULL DEFAULT 'Bronce',
    fecha_ultimo_pedido DATETIME NULL,
    activo            BOOLEAN NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- Entidad: Productos
-- ----------------------------------------------------------------------------
CREATE TABLE productos (
    id_producto       INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(150) NOT NULL UNIQUE,
    descripcion       TEXT NULL,
    precio            DECIMAL(10,2) NOT NULL,
    costo             DECIMAL(10,2) NOT NULL,
    stock             INT NOT NULL DEFAULT 0,
    stock_minimo      INT NOT NULL DEFAULT 5,
    peso_kg           DECIMAL(6,2) NOT NULL DEFAULT 0.50,
    sku               VARCHAR(50) NOT NULL UNIQUE,
    id_categoria      INT NULL,
    id_proveedor      INT NULL,
    fecha_creacion    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion DATETIME NULL,
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_precio_positivo CHECK (precio > 0),
    CONSTRAINT chk_costo_no_negativo CHECK (costo >= 0),
    CONSTRAINT chk_stock_no_negativo CHECK (stock >= 0),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria)
        REFERENCES categorias(id_categoria) ON DELETE RESTRICT,
    CONSTRAINT fk_producto_proveedor FOREIGN KEY (id_proveedor)
        REFERENCES proveedores(id_proveedor) ON DELETE SET NULL
);

-- ----------------------------------------------------------------------------
-- Entidad: Ventas (encabezado)
-- ----------------------------------------------------------------------------
CREATE TABLE ventas (
    id_venta        INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente      INT NOT NULL,
    id_sucursal     INT NULL,
    fecha_venta     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado          ENUM('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')
                    NOT NULL DEFAULT 'Pendiente de Pago',
    total           DECIMAL(12,2) NOT NULL DEFAULT 0,
    eliminado       BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_eliminacion DATETIME NULL,
    CONSTRAINT fk_venta_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes(id_cliente) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- Entidad: Detalle de Ventas
-- ----------------------------------------------------------------------------
CREATE TABLE detalle_ventas (
    id_detalle               INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                 INT NOT NULL,
    id_producto               INT NOT NULL,
    cantidad                 INT NOT NULL,
    precio_unitario_congelado DECIMAL(10,2) NOT NULL,
    CONSTRAINT chk_cantidad_positiva CHECK (cantidad > 0),
    CONSTRAINT fk_detalle_venta FOREIGN KEY (id_venta)
        REFERENCES ventas(id_venta) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- Tablas de apoyo (requeridas por las consultas, triggers, eventos y SPs
-- descritos en el enunciado del proyecto)
-- ----------------------------------------------------------------------------

-- Carritos de compra (para el análisis de carritos abandonados)
CREATE TABLE carritos (
    id_carrito     INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente     INT NOT NULL,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado         ENUM('Activo','Abandonado','Convertido') NOT NULL DEFAULT 'Activo',
    CONSTRAINT fk_carrito_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes(id_cliente) ON DELETE CASCADE
);

CREATE TABLE detalle_carrito (
    id_detalle_carrito INT AUTO_INCREMENT PRIMARY KEY,
    id_carrito         INT NOT NULL,
    id_producto        INT NOT NULL,
    cantidad           INT NOT NULL DEFAULT 1,
    fecha_agregado     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_detcarrito_carrito FOREIGN KEY (id_carrito)
        REFERENCES carritos(id_carrito) ON DELETE CASCADE,
    CONSTRAINT fk_detcarrito_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE
);

-- Vistas de producto (para "más vistos vs. comprados")
CREATE TABLE producto_vistas (
    id_vista    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente  INT NULL,
    fecha_vista DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_vista_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE,
    CONSTRAINT fk_vista_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes(id_cliente) ON DELETE SET NULL
);

-- Promociones (para el análisis de impacto de promociones)
CREATE TABLE promociones (
    id_promocion        INT AUTO_INCREMENT PRIMARY KEY,
    id_producto          INT NOT NULL,
    porcentaje_descuento DECIMAL(5,2) NOT NULL,
    fecha_inicio         DATETIME NOT NULL,
    fecha_fin            DATETIME NOT NULL,
    activo               BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_promocion_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE
);

-- Reseñas de productos
CREATE TABLE resenas (
    id_resena    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    id_cliente   INT NOT NULL,
    calificacion TINYINT NOT NULL,
    comentario   TEXT NULL,
    fecha_resena DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_calificacion CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT fk_resena_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE,
    CONSTRAINT fk_resena_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes(id_cliente) ON DELETE CASCADE
);

-- Programa de referidos
CREATE TABLE referidos (
    id_referido         INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente_referidor INT NOT NULL,
    id_cliente_referido  INT NOT NULL,
    fecha                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_referidor FOREIGN KEY (id_cliente_referidor)
        REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    CONSTRAINT fk_referido FOREIGN KEY (id_cliente_referido)
        REFERENCES clientes(id_cliente) ON DELETE CASCADE
);

-- Tasas de cambio (para fn_ConvertirMoneda)
CREATE TABLE tasas_cambio (
    id_tasa           INT AUTO_INCREMENT PRIMARY KEY,
    moneda_origen     CHAR(3) NOT NULL,
    moneda_destino    CHAR(3) NOT NULL,
    tasa              DECIMAL(12,6) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_par_monedas (moneda_origen, moneda_destino)
);

-- Alertas de stock bajo
CREATE TABLE alertas_stock (
    id_alerta    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    mensaje      VARCHAR(255) NOT NULL,
    fecha_alerta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atendida     BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_alerta_producto FOREIGN KEY (id_producto)
        REFERENCES productos(id_producto) ON DELETE CASCADE
);

-- Alertas de fraude
CREATE TABLE alertas_fraude (
    id_alerta_fraude INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente       INT NOT NULL,
    descripcion      VARCHAR(255) NOT NULL,
    fecha            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fraude_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes(id_cliente) ON DELETE CASCADE
);

-- Auditoría: nuevos clientes
CREATE TABLE auditoria_clientes (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    accion       VARCHAR(50) NOT NULL,
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Auditoría: intentos de inicio de sesión
CREATE TABLE auditoria_login (
    id_intento INT AUTO_INCREMENT PRIMARY KEY,
    usuario    VARCHAR(150) NOT NULL,
    exitoso    BOOLEAN NOT NULL,
    fecha      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_origen  VARCHAR(45) NULL
);

-- Auditoría: cambios de permisos
CREATE TABLE auditoria_permisos (
    id_auditoria     INT AUTO_INCREMENT PRIMARY KEY,
    usuario_afectado VARCHAR(150) NOT NULL,
    accion           VARCHAR(255) NOT NULL,
    fecha            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Auditoría: cambios de estado de pedido
CREATE TABLE auditoria_estado_pedido (
    id_auditoria    INT AUTO_INCREMENT PRIMARY KEY,
    id_venta        INT NOT NULL,
    estado_anterior VARCHAR(30) NOT NULL,
    estado_nuevo    VARCHAR(30) NOT NULL,
    fecha           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_auditoria_venta FOREIGN KEY (id_venta)
        REFERENCES ventas(id_venta) ON DELETE CASCADE
);

-- Archivo de ventas eliminadas
CREATE TABLE ventas_archivadas (
    id_archivo       INT AUTO_INCREMENT PRIMARY KEY,
    id_venta_original INT NOT NULL,
    id_cliente       INT NOT NULL,
    fecha_venta      DATETIME NOT NULL,
    estado           VARCHAR(30) NOT NULL,
    total            DECIMAL(12,2) NOT NULL,
    fecha_archivo    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- KPIs mensuales calculados
CREATE TABLE kpis_mensuales (
    id_kpi          INT AUTO_INCREMENT PRIMARY KEY,
    anio            INT NOT NULL,
    mes             INT NOT NULL,
    ventas_totales  DECIMAL(14,2) NOT NULL DEFAULT 0,
    nuevos_clientes INT NOT NULL DEFAULT 0,
    ticket_promedio DECIMAL(12,2) NOT NULL DEFAULT 0,
    fecha_calculo   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_anio_mes (anio, mes)
);

-- Historial de tamaño de la base de datos
CREATE TABLE tamano_bd_historico (
    id_registro INT AUTO_INCREMENT PRIMARY KEY,
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tamano_mb   DECIMAL(12,2) NOT NULL
);

-- Reporte de rendimiento de proveedores
CREATE TABLE reporte_rendimiento_proveedores (
    id_reporte     INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor   INT NOT NULL,
    anio           INT NOT NULL,
    mes            INT NOT NULL,
    total_vendido  DECIMAL(14,2) NOT NULL DEFAULT 0,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reporte_proveedor FOREIGN KEY (id_proveedor)
        REFERENCES proveedores(id_proveedor) ON DELETE CASCADE
);

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- DATOS DE EJEMPLO
-- ============================================================================

-- Categorías
INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Dispositivos y accesorios electrónicos'),
('Ropa', 'Prendas de vestir para todas las edades'),
('Hogar', 'Artículos para el hogar y la cocina'),
('Deportes', 'Equipamiento y ropa deportiva'),
('General', 'Categoría por defecto para productos sin clasificar');

-- Proveedores
INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechImport S.A.S', 'ventas@techimport.com', '3001234567'),
('Textiles del Valle', 'contacto@textilesvalle.com', '3012345678'),
('Hogar y Confort Ltda', 'info@hogarconfort.com', '3023456789'),
('DeporMax', 'contacto@deportmax.com', '3034567890');

-- Clientes
INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad, fecha_nacimiento, id_sucursal, total_gastado, nivel_lealtad) VALUES
('Laura', 'Gómez', 'laura.gomez@correo.com', SHA2('clave123', 256), 'Cra 10 #20-30', 'Bucaramanga', '1995-03-14', 1, 0, 'Bronce'),
('Carlos', 'Ramírez', 'carlos.ramirez@correo.com', SHA2('clave123', 256), 'Cll 45 #12-08', 'Bogotá', '1988-07-22', 2, 0, 'Bronce'),
('Mariana', 'Torres', 'mariana.torres@correo.com', SHA2('clave123', 256), 'Av 30 #5-40', 'Medellín', '1992-11-02', 1, 0, 'Bronce'),
('Andrés', 'López', 'andres.lopez@correo.com', SHA2('clave123', 256), 'Cra 7 #80-15', 'Cali', '1999-01-30', 3, 0, 'Bronce'),
('Sofía', 'Martínez', 'sofia.martinez@correo.com', SHA2('clave123', 256), 'Cll 100 #10-20', 'Bucaramanga', '1990-05-18', 1, 0, 'Bronce');

-- Productos
INSERT INTO productos (nombre, descripcion, precio, costo, stock, stock_minimo, peso_kg, sku, id_categoria, id_proveedor) VALUES
('Audífonos Bluetooth X200', 'Audífonos inalámbricos con cancelación de ruido', 149900, 80000, 40, 10, 0.30, 'ELEC-001', 1, 1),
('Smartwatch FitPro', 'Reloj inteligente con monitor de ritmo cardíaco', 289900, 150000, 25, 8, 0.15, 'ELEC-002', 1, 1),
('Camiseta Deportiva DryFit', 'Camiseta transpirable para entrenamiento', 59900, 22000, 100, 20, 0.20, 'ROPA-001', 2, 2),
('Chaqueta Impermeable', 'Chaqueta ligera resistente al agua', 189900, 90000, 30, 10, 0.60, 'ROPA-002', 2, 2),
('Juego de Sartenes Antiadherentes', 'Set de 3 sartenes de aluminio', 129900, 65000, 15, 5, 2.50, 'HOG-001', 3, 3),
('Lámpara de Escritorio LED', 'Lámpara regulable con puerto USB', 79900, 35000, 50, 15, 0.80, 'HOG-002', 3, 3),
('Balón de Fútbol Profesional', 'Balón oficial talla 5', 99900, 45000, 60, 15, 0.45, 'DEP-001', 4, 4),
('Mancuernas Ajustables 10kg', 'Par de mancuernas con discos intercambiables', 219900, 110000, 20, 5, 10.00, 'DEP-002', 4, 4),
('Cargador Inalámbrico Rápido', 'Base de carga rápida Qi 15W', 69900, 28000, 45, 10, 0.20, 'ELEC-003', 1, 1),
('Pantalón Jogger', 'Pantalón deportivo cómodo y ligero', 89900, 34000, 70, 15, 0.35, 'ROPA-003', 2, 2);

-- Ventas y detalle de ventas (datos de ejemplo)
INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado, total) VALUES
(1, 1, '2026-06-05 10:15:00', 'Entregado', 209800),
(2, 2, '2026-06-10 14:30:00', 'Entregado', 289900),
(1, 1, '2026-07-02 09:00:00', 'Entregado', 149900),
(3, 1, '2026-07-15 16:45:00', 'Enviado', 279800),
(4, 3, '2026-08-01 11:20:00', 'Procesando', 99900),
(5, 1, '2026-08-20 13:10:00', 'Pendiente de Pago', 159800),
(2, 2, '2026-09-01 10:00:00', 'Entregado', 219900),
(1, 1, '2026-09-10 15:30:00', 'Entregado', 69900);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 149900),
(1, 3, 1, 59900),
(2, 2, 1, 289900),
(3, 1, 1, 149900),
(4, 4, 1, 189900),
(4, 3, 1, 59900),
(4, 6, 1, 79900),
(5, 7, 1, 99900),
(6, 6, 2, 79900),
(7, 8, 1, 219900),
(8, 9, 1, 69900);

-- Vistas de producto (para análisis de "vistos vs. comprados")
INSERT INTO producto_vistas (id_producto, id_cliente, fecha_vista) VALUES
(1, 1, '2026-06-04 09:00:00'),
(1, 3, '2026-07-14 18:00:00'),
(2, 2, '2026-06-09 20:00:00'),
(5, 4, '2026-08-01 08:00:00'),
(5, 5, '2026-08-19 12:00:00'),
(10, 1, '2026-09-09 21:00:00');

-- Carrito de compra activo/abandonado de ejemplo
INSERT INTO carritos (id_cliente, fecha_creacion, estado) VALUES
(4, '2026-09-18 10:00:00', 'Activo'),
(5, '2026-09-01 09:00:00', 'Abandonado');

INSERT INTO detalle_carrito (id_carrito, id_producto, cantidad, fecha_agregado) VALUES
(1, 2, 1, '2026-09-18 10:05:00'),
(2, 10, 2, '2026-09-01 09:10:00');

-- Promoción de ejemplo
INSERT INTO promociones (id_producto, porcentaje_descuento, fecha_inicio, fecha_fin, activo) VALUES
(1, 15.00, '2026-05-20 00:00:00', '2026-06-05 23:59:59', FALSE);

-- Tasa de cambio de ejemplo
INSERT INTO tasas_cambio (moneda_origen, moneda_destino, tasa) VALUES
('COP', 'USD', 0.00025),
('USD', 'COP', 4000.00);

-- Reseña de ejemplo
INSERT INTO resenas (id_producto, id_cliente, calificacion, comentario) VALUES
(1, 1, 5, 'Excelente calidad de sonido.'),
(2, 2, 4, 'Muy buena batería, cómodo de usar.');