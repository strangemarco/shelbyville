-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 05: Datos Semilla Iniciales (Seed Data)
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. INSERTAR ROLES DEL SISTEMA
INSERT INTO public.roles (id, nombre, descripcion)
VALUES 
    ('admin', 'Administrador', 'Control total de configuración, usuarios, inventario, caja y reportes.'),
    ('cajero', 'Cajero / Operador', 'Gestión de mesas, toma de consumos, cobro de cuentas y arqueo de caja.')
ON CONFLICT (id) DO UPDATE SET 
    nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion;


-- 2. INSERTAR TARIFAS INICIALES
INSERT INTO public.tarifas (id, nombre, descripcion, precio_por_hora, minutos_minimo, minutos_tolerancia, activo)
VALUES 
    ('11111111-1111-1111-1111-111111111101', 'Tarifa Estándar (Pool)', 'Tarifa regular por hora para mesas de pool bola 8 y 9.', 25.00, 15, 5, true),
    ('11111111-1111-1111-1111-111111111102', 'Tarifa Promo Tarde', 'Tarifa reducida para horario diurno y promociones.', 18.00, 15, 5, true),
    ('11111111-1111-1111-1111-111111111103', 'Tarifa Noche y Finde', 'Tarifa para viernes, sábados y horarios de alta demanda.', 30.00, 15, 5, true),
    ('11111111-1111-1111-1111-111111111104', 'Tarifa Carambola y Snooker VIP', 'Tarifa para mesas profesionales de 3 bandas y snooker.', 35.00, 20, 5, true)
ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    precio_por_hora = EXCLUDED.precio_por_hora;


-- 3. INSERTAR MESAS DE BILLAR
INSERT INTO public.mesas (id, numero, nombre, tipo, tarifa_defecto_id, estado, activa)
VALUES 
    ('22222222-2222-2222-2222-222222222201', 1, 'Mesa 1 - Pool Clásica', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222202', 2, 'Mesa 2 - Pool Clásica', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222203', 3, 'Mesa 3 - Pool Central', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222204', 4, 'Mesa 4 - Pool Central', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222205', 5, 'Mesa 5 - Pool Pro', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222206', 6, 'Mesa 6 - Pool Pro', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222207', 7, 'Mesa 7 - Carambola 3 Bandas', 'Carambola', '11111111-1111-1111-1111-111111111104', 'disponible', true),
    ('22222222-2222-2222-2222-222222222208', 8, 'Mesa 8 - Snooker VIP', 'Snooker', '11111111-1111-1111-1111-111111111104', 'disponible', true)
ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    tipo = EXCLUDED.tipo;


-- 4. INSERTAR CATEGORIAS DE PRODUCTOS
INSERT INTO public.categorias (id, nombre, descripcion, icono, orden, activo)
VALUES 
    ('33333333-3333-3333-3333-333333333301', 'Cervezas', 'Cervezas nacionales, artesanales e importadas.', 'Beer', 1, true),
    ('33333333-3333-3333-3333-333333333302', 'Bebidas & Gaseosas', 'Gaseosas, aguas y energizantes.', 'CupSoda', 2, true),
    ('33333333-3333-3333-3333-333333333303', 'Snacks & Piqueos', 'Papas fritas, nachos, maní y piqueos rápidos.', 'Utensils', 3, true),
    ('33333333-3333-3333-3333-333333333304', 'Tragos & Licores', 'Vasos y jarras de combinados, fernet, whisky y cocteles.', 'Wine', 4, true),
    ('33333333-3333-3333-3333-333333333305', 'Varios', 'Cigarrillos, encendedores y accesorios.', 'Package', 5, true)
ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    icono = EXCLUDED.icono;


-- 5. INSERTAR PRODUCTOS INICIALES CON STOCK
INSERT INTO public.productos (id, categoria_id, codigo, nombre, descripcion, precio_compra, precio_venta, stock, stock_minimo, activo)
VALUES 
    -- Cervezas
    ('44444444-4444-4444-4444-444444444401', '33333333-3333-3333-3333-333333333301', 'CER-01', 'Cerveza Corona 355ml', 'Botella individual fría', 12.00, 20.00, 48, 12, true),
    ('44444444-4444-4444-4444-444444444402', '33333333-3333-3333-3333-333333333301', 'CER-02', 'Cerveza Heineken 330ml', 'Botella individual fría', 12.00, 20.00, 36, 12, true),
    ('44444444-4444-4444-4444-444444444403', '33333333-3333-3333-3333-333333333301', 'CER-03', 'Cerveza Paceña Huari 330ml', 'Cerveza tradicional', 10.00, 18.00, 60, 15, true),
    
    -- Bebidas no alcohólicas
    ('44444444-4444-4444-4444-444444444404', '33333333-3333-3333-3333-333333333302', 'BEB-01', 'Coca Cola 500ml', 'Botella personal', 5.00, 10.00, 40, 10, true),
    ('44444444-4444-4444-4444-444444444405', '33333333-3333-3333-3333-333333333302', 'BEB-02', 'Sprite 500ml', 'Botella personal', 5.00, 10.00, 25, 8, true),
    ('44444444-4444-4444-4444-444444444406', '33333333-3333-3333-3333-333333333302', 'BEB-03', 'Agua Mineral 500ml', 'Con gas / Sin gas', 4.00, 8.00, 30, 10, true),
    ('44444444-4444-4444-4444-444444444407', '33333333-3333-3333-3333-333333333302', 'BEB-04', 'Red Bull 250ml', 'Lata energizante clásica', 14.00, 25.00, 24, 6, true),

    -- Snacks
    ('44444444-4444-4444-4444-444444444408', '33333333-3333-3333-3333-333333333303', 'SNK-01', 'Papas Fritas Lays 90g', 'Bolsa mediana clásico corte fino', 6.00, 12.00, 20, 5, true),
    ('44444444-4444-4444-4444-444444444409', '33333333-3333-3333-3333-333333333303', 'SNK-02', 'Nachos con Queso Cheddar', 'Porción para mesa con dip caliente', 10.00, 22.00, 15, 4, true),
    ('44444444-4444-4444-4444-444444444410', '33333333-3333-3333-3333-333333333303', 'SNK-03', 'Maní Tostado Salado 100g', 'Piqueo clásico para billar', 4.00, 8.00, 35, 10, true),

    -- Tragos
    ('44444444-4444-4444-4444-444444444411', '33333333-3333-3333-3333-333333333304', 'TRG-01', 'Fernet Branca con Coca', 'Vaso largo con hielo', 12.00, 25.00, 80, 20, true),
    ('44444444-4444-4444-4444-444444444412', '33333333-3333-3333-3333-333333333304', 'TRG-02', 'Whisky Red Label (Vaso)', 'Vaso con hielo o agua con gas', 15.00, 30.00, 50, 10, true)
ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    precio_venta = EXCLUDED.precio_venta,
    stock = EXCLUDED.stock;
