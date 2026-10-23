-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 04: Seguridad y Políticas Row Level Security (RLS)
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. HABILITAR ROW LEVEL SECURITY EN TODAS LAS TABLAS
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tarifas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mesas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sesiones_billar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pausas_sesion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_inventario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consumos_mesa ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cajas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_caja ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.detalles_venta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria ENABLE ROW LEVEL SECURITY;

-- 2. FUNCIONES DE AYUDA PARA VERIFICAR ROLES
CREATE OR REPLACE FUNCTION public.fn_es_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.perfiles 
        WHERE id = auth.uid() AND rol_id = 'admin' AND activo = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.fn_usuario_autenticado_activo()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.perfiles 
        WHERE id = auth.uid() AND activo = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;


-- 3. POLÍTICAS PARA ROLES Y PERFILES
DROP POLICY IF EXISTS "Lectura de roles para usuarios autenticados" ON public.roles;
CREATE POLICY "Lectura de roles para usuarios autenticados"
    ON public.roles FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Lectura de perfiles para usuarios autenticados" ON public.perfiles;
CREATE POLICY "Lectura de perfiles para usuarios autenticados"
    ON public.perfiles FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Usuarios editan su propio perfil" ON public.perfiles;
CREATE POLICY "Usuarios editan su propio perfil"
    ON public.perfiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Admins gestionan perfiles" ON public.perfiles;
CREATE POLICY "Admins gestionan perfiles"
    ON public.perfiles FOR ALL
    TO authenticated
    USING (public.fn_es_admin())
    WITH CHECK (public.fn_es_admin());


-- 4. POLÍTICAS PARA MESAS Y TARIFAS
DROP POLICY IF EXISTS "Lectura de mesas para autenticados" ON public.mesas;
CREATE POLICY "Lectura de mesas para autenticados"
    ON public.mesas FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Admins administran mesas" ON public.mesas;
CREATE POLICY "Admins administran mesas"
    ON public.mesas FOR ALL
    TO authenticated
    USING (public.fn_es_admin())
    WITH CHECK (public.fn_es_admin());

DROP POLICY IF EXISTS "Lectura de tarifas para autenticados" ON public.tarifas;
CREATE POLICY "Lectura de tarifas para autenticados"
    ON public.tarifas FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Admins administran tarifas" ON public.tarifas;
CREATE POLICY "Admins administran tarifas"
    ON public.tarifas FOR ALL
    TO authenticated
    USING (public.fn_es_admin())
    WITH CHECK (public.fn_es_admin());


-- 5. POLÍTICAS PARA PRODUCTOS Y CATEGORIAS
DROP POLICY IF EXISTS "Lectura de categorias para autenticados" ON public.categorias;
CREATE POLICY "Lectura de categorias para autenticados"
    ON public.categorias FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Admins gestionan categorias" ON public.categorias;
CREATE POLICY "Admins gestionan categorias"
    ON public.categorias FOR ALL
    TO authenticated
    USING (public.fn_es_admin())
    WITH CHECK (public.fn_es_admin());

DROP POLICY IF EXISTS "Lectura de productos para autenticados" ON public.productos;
CREATE POLICY "Lectura de productos para autenticados"
    ON public.productos FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Admins gestionan productos" ON public.productos;
CREATE POLICY "Admins gestionan productos"
    ON public.productos FOR ALL
    TO authenticated
    USING (public.fn_es_admin())
    WITH CHECK (public.fn_es_admin());


-- 6. POLÍTICAS PARA SESIONES DE BILLAR Y CONSUMOS
DROP POLICY IF EXISTS "Acceso a sesiones para personal activo" ON public.sesiones_billar;
CREATE POLICY "Acceso a sesiones para personal activo"
    ON public.sesiones_billar FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Acceso a pausas para personal activo" ON public.pausas_sesion;
CREATE POLICY "Acceso a pausas para personal activo"
    ON public.pausas_sesion FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Acceso a consumos de mesa para personal activo" ON public.consumos_mesa;
CREATE POLICY "Acceso a consumos de mesa para personal activo"
    ON public.consumos_mesa FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());


-- 7. POLÍTICAS PARA CAJA Y MOVIMIENTOS
DROP POLICY IF EXISTS "Acceso a cajas para personal activo" ON public.cajas;
CREATE POLICY "Acceso a cajas para personal activo"
    ON public.cajas FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Acceso a movimientos de caja para personal activo" ON public.movimientos_caja;
CREATE POLICY "Acceso a movimientos de caja para personal activo"
    ON public.movimientos_caja FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());


-- 8. POLÍTICAS PARA VENTAS Y PAGOS
DROP POLICY IF EXISTS "Acceso a ventas para personal activo" ON public.ventas;
CREATE POLICY "Acceso a ventas para personal activo"
    ON public.ventas FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Acceso a detalles de venta para personal activo" ON public.detalles_venta;
CREATE POLICY "Acceso a detalles de venta para personal activo"
    ON public.detalles_venta FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Acceso a pagos para personal activo" ON public.pagos;
CREATE POLICY "Acceso a pagos para personal activo"
    ON public.pagos FOR ALL
    TO authenticated
    USING (public.fn_usuario_autenticado_activo())
    WITH CHECK (public.fn_usuario_autenticado_activo());


-- 9. POLÍTICAS PARA INVENTARIO Y AUDITORIA
DROP POLICY IF EXISTS "Lectura de kardex para personal activo" ON public.movimientos_inventario;
CREATE POLICY "Lectura de kardex para personal activo"
    ON public.movimientos_inventario FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

DROP POLICY IF EXISTS "Lectura de auditoria para administradores" ON public.auditoria;
CREATE POLICY "Lectura de auditoria para administradores"
    ON public.auditoria FOR SELECT
    TO authenticated
    USING (public.fn_es_admin());

-- 10. PERMISOS GENERALES A ESQUEMA PUBLIC
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
