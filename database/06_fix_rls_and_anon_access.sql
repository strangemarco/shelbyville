-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 06: Ajuste de Permisos y RLS para Modo Terminal / Anon y Authenticated
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. PERMITIR CAJA EN MODO TERMINAL (usuario opcional)
ALTER TABLE public.cajas ALTER COLUMN usuario_apertura_id DROP NOT NULL;

-- 2. POLÍTICAS DE LECTURA Y ESCRITURA PARA MESAS Y TARIFAS
DROP POLICY IF EXISTS "Lectura de mesas para autenticados" ON public.mesas;
DROP POLICY IF EXISTS "Admins administran mesas" ON public.mesas;
DROP POLICY IF EXISTS "Lectura de mesas para todos" ON public.mesas;
DROP POLICY IF EXISTS "Acceso total a mesas" ON public.mesas;

CREATE POLICY "Acceso total a mesas"
    ON public.mesas FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Lectura de tarifas para autenticados" ON public.tarifas;
DROP POLICY IF EXISTS "Admins administran tarifas" ON public.tarifas;
DROP POLICY IF EXISTS "Acceso total a tarifas" ON public.tarifas;

CREATE POLICY "Acceso total a tarifas"
    ON public.tarifas FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 3. POLÍTICAS PARA PRODUCTOS Y CATEGORÍAS
DROP POLICY IF EXISTS "Lectura de categorias para autenticados" ON public.categorias;
DROP POLICY IF EXISTS "Admins gestionan categorias" ON public.categorias;
DROP POLICY IF EXISTS "Acceso total a categorias" ON public.categorias;

CREATE POLICY "Acceso total a categorias"
    ON public.categorias FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Lectura de productos para autenticados" ON public.productos;
DROP POLICY IF EXISTS "Admins gestionan productos" ON public.productos;
DROP POLICY IF EXISTS "Acceso total a productos" ON public.productos;

CREATE POLICY "Acceso total a productos"
    ON public.productos FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 4. POLÍTICAS PARA SESIONES, PAUSAS Y CONSUMOS
DROP POLICY IF EXISTS "Acceso a sesiones para personal activo" ON public.sesiones_billar;
DROP POLICY IF EXISTS "Acceso total a sesiones" ON public.sesiones_billar;

CREATE POLICY "Acceso total a sesiones"
    ON public.sesiones_billar FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso a pausas para personal activo" ON public.pausas_sesion;
DROP POLICY IF EXISTS "Acceso total a pausas" ON public.pausas_sesion;

CREATE POLICY "Acceso total a pausas"
    ON public.pausas_sesion FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso a consumos de mesa para personal activo" ON public.consumos_mesa;
DROP POLICY IF EXISTS "Acceso total a consumos" ON public.consumos_mesa;

CREATE POLICY "Acceso total a consumos"
    ON public.consumos_mesa FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 5. POLÍTICAS PARA CAJA Y MOVIMIENTOS
DROP POLICY IF EXISTS "Acceso a cajas para personal activo" ON public.cajas;
DROP POLICY IF EXISTS "Acceso total a cajas" ON public.cajas;

CREATE POLICY "Acceso total a cajas"
    ON public.cajas FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso a movimientos de caja para personal activo" ON public.movimientos_caja;
DROP POLICY IF EXISTS "Acceso total a movimientos de caja" ON public.movimientos_caja;

CREATE POLICY "Acceso total a movimientos de caja"
    ON public.movimientos_caja FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 6. POLÍTICAS PARA VENTAS, DETALLES Y PAGOS
DROP POLICY IF EXISTS "Acceso a ventas para personal activo" ON public.ventas;
DROP POLICY IF EXISTS "Acceso total a ventas" ON public.ventas;

CREATE POLICY "Acceso total a ventas"
    ON public.ventas FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso a detalles de venta para personal activo" ON public.detalles_venta;
DROP POLICY IF EXISTS "Acceso total a detalles de venta" ON public.detalles_venta;

CREATE POLICY "Acceso total a detalles de venta"
    ON public.detalles_venta FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso a pagos para personal activo" ON public.pagos;
DROP POLICY IF EXISTS "Acceso total a pagos" ON public.pagos;

CREATE POLICY "Acceso total a pagos"
    ON public.pagos FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 7. POLÍTICAS PARA INVENTARIO
DROP POLICY IF EXISTS "Lectura de kardex para personal activo" ON public.movimientos_inventario;
DROP POLICY IF EXISTS "Acceso total a movimientos de inventario" ON public.movimientos_inventario;

CREATE POLICY "Acceso total a movimientos de inventario"
    ON public.movimientos_inventario FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 8. PERMISOS Y PRIVILEGIOS TOTALES AL ROL ANON Y AUTHENTICATED
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
