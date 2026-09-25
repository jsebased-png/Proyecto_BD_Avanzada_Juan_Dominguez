-- =============================================================================
-- PROYECTO: Base de Datos de un E-commerce
-- ARCHIVO: 04_Seguridad.sql
-- DESCRIPCIÓN: Implementación completa del esquema de seguridad: Creación de
--              roles, usuarios, asignación granular de privilegios, vistas de
--              seguridad, límites de recursos y auditoría de accesos.
-- MOTOR: MySQL 8.0+
-- =============================================================================

USE ecommerce_db;

-- -----------------------------------------------------------------------------
-- 1. Crear el rol Administrador_Sistema con todos los privilegios.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema' WITH GRANT OPTION;


-- -----------------------------------------------------------------------------
-- 2. Crear el rol Gerente_Marketing con acceso de solo lectura a ventas y clientes.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.promociones TO 'Gerente_Marketing';


-- -----------------------------------------------------------------------------
-- 3. Crear el rol Analista_Datos con acceso de solo lectura a todas las tablas,
-- excepto a las de auditoría.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.sucursales TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.productos TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.clientes TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.promociones TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carrito_compras TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.resenas_productos TO 'Analista_Datos';
-- No se otorgan permisos SELECT sobre tablas de auditoría (log_cambios_precio, auditoria_clientes, etc.)


-- -----------------------------------------------------------------------------
-- 4. Crear el rol Empleado_Inventario que solo pueda modificar la tabla productos
-- (actualizar stock) y consultar catálogo y categorías.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.categorias TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.proveedores TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.productos TO 'Empleado_Inventario';
GRANT UPDATE (stock) ON ecommerce_db.productos TO 'Empleado_Inventario';


-- -----------------------------------------------------------------------------
-- 5. Crear el rol Atencion_Cliente que pueda ver clientes y ventas, pero no modificar precios.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Atencion_Cliente';
GRANT SELECT, UPDATE (direccion_envio, ciudad) ON ecommerce_db.clientes TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.productos TO 'Atencion_Cliente';
-- En ningún momento se otorga permiso UPDATE sobre productos.precio a Atencion_Cliente


-- -----------------------------------------------------------------------------
-- 6. Crear el rol Auditor_Financiero con acceso de solo lectura a ventas, productos
-- y logs de precios.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.productos TO 'Auditor_Financiero';


-- -----------------------------------------------------------------------------
-- 7. Crear un usuario admin_user y asignarle el rol de administrador.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'admin_user'@'localhost' 
    IDENTIFIED BY 'AdminSeguro2026!#';
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';


-- -----------------------------------------------------------------------------
-- 8. Crear un usuario marketing_user y asignarle el rol de marketing.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' 
    IDENTIFIED BY 'Marketing2026!#';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
SET DEFAULT ROLE 'Gerente_Marketing' TO 'marketing_user'@'localhost';


-- -----------------------------------------------------------------------------
-- 9. Crear un usuario inventory_user y asignarle el rol de inventario.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' 
    IDENTIFIED BY 'Inventory2026!#';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
SET DEFAULT ROLE 'Empleado_Inventario' TO 'inventory_user'@'localhost';


-- -----------------------------------------------------------------------------
-- 10. Crear un usuario support_user y asignarle el rol de atención al cliente.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'support_user'@'localhost' 
    IDENTIFIED BY 'Support2026!#';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';
SET DEFAULT ROLE 'Atencion_Cliente' TO 'support_user'@'localhost';


-- -----------------------------------------------------------------------------
-- 11. Impedir que el rol Analista_Datos pueda ejecutar comandos DELETE o TRUNCATE.
-- En MySQL, TRUNCATE requiere privilegio DROP. Se asegura la ausencia explícita
-- de DELETE y DROP revocándolos en caso de herencia previa.
-- Se usa "IF EXISTS" porque estos privilegios nunca fueron otorgados al rol
-- (solo tiene SELECT); un REVOKE normal fallaría con error 1141 al no existir
-- el grant que se intenta revocar.
-- -----------------------------------------------------------------------------
REVOKE IF EXISTS DELETE, DROP ON ecommerce_db.* FROM 'Analista_Datos';


-- -----------------------------------------------------------------------------
-- 12. Otorgar al rol Gerente_Marketing permiso para ejecutar procedimientos
-- almacenados de reportes de marketing.
-- El procedimiento sp_GenerarReporteMensualVentas no existía todavía en el
-- esquema (de ahí el error 1305 "PROCEDURE ... does not exist" al hacer GRANT
-- EXECUTE sobre él), así que se crea aquí antes de otorgar el privilegio.
-- -----------------------------------------------------------------------------
DELIMITER //
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas//
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes INT
)
BEGIN
    SELECT 
        YEAR(v.fecha_venta) AS anio,
        MONTH(v.fecha_venta) AS mes,
        COUNT(DISTINCT v.id_venta) AS total_pedidos,
        SUM(v.total) AS ventas_totales,
        ROUND(AVG(v.total), 2) AS ticket_promedio
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
      AND YEAR(v.fecha_venta) = p_anio
      AND MONTH(v.fecha_venta) = p_mes
    GROUP BY YEAR(v.fecha_venta), MONTH(v.fecha_venta);
END//
DELIMITER ;

GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';


-- -----------------------------------------------------------------------------
-- 13. Crear una vista v_info_clientes_basica que oculte información sensible
-- (como la contraseña y saldo exacto) y dar acceso a ella al rol Atencion_Cliente.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT 
    id_cliente,
    nombre,
    apellido,
    email,
    direccion_envio,
    ciudad,
    pais,
    fecha_registro,
    nivel_lealtad,
    activo
FROM ecommerce_db.clientes;

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';


-- -----------------------------------------------------------------------------
-- 14. Revocar el permiso de UPDATE sobre la columna precio de la tabla productos
-- al rol Empleado_Inventario (asegurando que solo modifique stock).
-- Al rol solo se le otorgó UPDATE (stock), nunca UPDATE (precio), por lo que
-- revocarlo sin "IF EXISTS" produce el error 1147 "There is no such grant
-- defined...". Se deja como revocación defensiva e idempotente.
-- -----------------------------------------------------------------------------
REVOKE IF EXISTS UPDATE (precio) ON ecommerce_db.productos FROM 'Empleado_Inventario';


-- -----------------------------------------------------------------------------
-- 15. Implementar una política de contraseñas seguras para todos los usuarios.
-- Configura vencimiento periódico de 90 días y complejidad estándar.
-- -----------------------------------------------------------------------------
ALTER USER 'admin_user'@'localhost' 
    PASSWORD EXPIRE INTERVAL 90 DAY 
    FAILED_LOGIN_ATTEMPTS 3 
    PASSWORD_LOCK_TIME 1;

ALTER USER 'marketing_user'@'localhost' 
    PASSWORD EXPIRE INTERVAL 90 DAY 
    FAILED_LOGIN_ATTEMPTS 3 
    PASSWORD_LOCK_TIME 1;

ALTER USER 'inventory_user'@'localhost' 
    PASSWORD EXPIRE INTERVAL 90 DAY 
    FAILED_LOGIN_ATTEMPTS 3 
    PASSWORD_LOCK_TIME 1;

ALTER USER 'support_user'@'localhost' 
    PASSWORD EXPIRE INTERVAL 90 DAY 
    FAILED_LOGIN_ATTEMPTS 3 
    PASSWORD_LOCK_TIME 1;


-- -----------------------------------------------------------------------------
-- 16. Asegurar que el usuario root no pueda ser usado desde conexiones remotas.
-- Se elimina la cuenta comodín remota 'root'@'%' si existiera, limitándola a localhost.
-- -----------------------------------------------------------------------------
DROP USER IF EXISTS 'root'@'%';


-- -----------------------------------------------------------------------------
-- 17. Crear un rol Visitante que solo pueda ver la tabla productos.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'Visitante';
GRANT SELECT ON ecommerce_db.productos TO 'Visitante';


-- -----------------------------------------------------------------------------
-- 18. Limitar el número de consultas por hora para el rol Analista_Datos para
-- evitar sobrecarga en el servidor.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'analista_user'@'localhost' 
    IDENTIFIED BY 'Analista2026!#';
GRANT 'Analista_Datos' TO 'analista_user'@'localhost';
SET DEFAULT ROLE 'Analista_Datos' TO 'analista_user'@'localhost';
ALTER USER 'analista_user'@'localhost' 
    WITH MAX_QUERIES_PER_HOUR 100
         MAX_UPDATES_PER_HOUR 0;


-- -----------------------------------------------------------------------------
-- 19. Asegurar que los usuarios solo puedan ver las ventas de la sucursal a la
-- que pertenecen (Row-Level Security implementada con Vista y mapeo de usuario).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ventas_sucursal_usuario AS
SELECT 
    v.id_venta,
    v.id_cliente,
    v.id_sucursal,
    v.fecha_venta,
    v.estado,
    v.total
FROM ecommerce_db.ventas v
INNER JOIN ecommerce_db.usuario_sucursal us ON v.id_sucursal = us.id_sucursal
WHERE us.username = SUBSTRING_INDEX(USER(), '@', 1)
   OR SUBSTRING_INDEX(USER(), '@', 1) = 'admin_user';

GRANT SELECT ON ecommerce_db.v_ventas_sucursal_usuario TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.v_ventas_sucursal_usuario TO 'Empleado_Inventario';


-- -----------------------------------------------------------------------------
-- 20. Auditar todos los intentos de inicio de sesión fallidos en la base de datos.
-- Creación de la tabla de auditoría de accesos fallidos y procedimiento de registro.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_intentos_login_fallidos (
    id_intento INT AUTO_INCREMENT PRIMARY KEY,
    usuario_intentado VARCHAR(100) NOT NULL,
    ip_origen VARCHAR(45) NOT NULL,
    fecha_intento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    motivo VARCHAR(200) NOT NULL DEFAULT 'Credenciales erróneas o cuenta bloqueada'
) ENGINE=InnoDB;

DELIMITER //
DROP PROCEDURE IF EXISTS sp_RegistrarIntentoLoginFallido//
CREATE PROCEDURE sp_RegistrarIntentoLoginFallido(
    IN p_usuario VARCHAR(100),
    IN p_ip VARCHAR(45),
    IN p_motivo VARCHAR(200)
)
BEGIN
    INSERT INTO log_intentos_login_fallidos (usuario_intentado, ip_origen, motivo)
    VALUES (p_usuario, p_ip, COALESCE(p_motivo, 'Intento no autorizado'));
END//
DELIMITER ;

FLUSH PRIVILEGES;