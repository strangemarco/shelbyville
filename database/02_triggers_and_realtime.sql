-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 02: Triggers automáticos y Configuración de Supabase Realtime
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. FUNCION GENERICA PARA ACTUALIZAR 'actualizado_en'
CREATE OR REPLACE FUNCTION public.fn_actualizar_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizado_en = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers de actualización de fecha
DROP TRIGGER IF EXISTS trg_upd_perfiles ON public.perfiles;
CREATE TRIGGER trg_upd_perfiles
    BEFORE UPDATE ON public.perfiles
    FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_tarifas ON public.tarifas;
CREATE TRIGGER trg_upd_tarifas
    BEFORE UPDATE ON public.tarifas
    FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_mesas ON public.mesas;
CREATE TRIGGER trg_upd_mesas
    BEFORE UPDATE ON public.mesas
    FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_sesiones_billar ON public.sesiones_billar;
CREATE TRIGGER trg_upd_sesiones_billar
    BEFORE UPDATE ON public.sesiones_billar
    FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_productos ON public.productos;
CREATE TRIGGER trg_upd_productos
    BEFORE UPDATE ON public.productos
    FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();


-- 2. TRIGGER PARA CREACION AUTOMATICA DE PERFIL AL REGISTRARSE EN SUPABASE AUTH
CREATE OR REPLACE FUNCTION public.fn_handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_total_usuarios INT;
    v_rol_asignado VARCHAR(30);
    v_nombre VARCHAR(150);
BEGIN
    SELECT COUNT(*) INTO v_total_usuarios FROM public.perfiles;
    
    -- El primer usuario registrado es automáticamente 'admin', los siguientes son 'cajero'
    IF v_total_usuarios = 0 THEN
        v_rol_asignado := 'admin';
    ELSE
        v_rol_asignado := 'cajero';
    END IF;

    -- Extraer nombre del metadata o usar el email como fallback
    v_nombre := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'nombre',
        SPLIT_PART(NEW.email, '@', 1)
    );

    INSERT INTO public.perfiles (id, rol_id, nombre_completo, activo)
    VALUES (NEW.id, v_rol_asignado, v_nombre, true)
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.fn_handle_new_user();


-- 3. HABILITACION DE SUPABASE REALTIME
-- Agrega las tablas operativas a la publicación de Realtime para actualizar la UI en vivo
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'mesas'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mesas;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'sesiones_billar'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.sesiones_billar;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'consumos_mesa'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.consumos_mesa;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'cajas'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.cajas;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'productos'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.productos;
    END IF;
END $$;
