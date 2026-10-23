-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 10: Módulo de Gestión de Usuarios, Perfiles y Roles
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. ASEGURAR EXTENSIONES CRIPTOGRÁFICAS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENRIQUECER LA TABLA DE ROLES CON CATÁLOGO COMPLETO
INSERT INTO public.roles (id, nombre, descripcion)
VALUES 
    ('admin', 'Administrador', 'Control total del club, configuración, tarifas, inventario, caja, reportes y gestión de usuarios.'),
    ('supervisor', 'Supervisor de Turno', 'Supervisión general de operaciones del salón, turnos de caja, stock y reportes.'),
    ('cajero', 'Cajero / Operador', 'Apertura y cobro de mesas, toma de pedidos, punto de venta directo y arqueos de caja.'),
    ('mesero', 'Mesero / Garzón', 'Atención en salón, registro de pedidos y consumos cargados a mesas activas.'),
    ('bartender', 'Bartender / Barra', 'Preparación de tragos, despacho de bebidas y control de stock en barra.')
ON CONFLICT (id) DO UPDATE SET 
    nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion;

-- 3. AJUSTES EN LA TABLA DE PERFILES
-- Agregar columna email si no existe para consulta ágil desde PostgREST
ALTER TABLE public.perfiles ADD COLUMN IF NOT EXISTS email VARCHAR(255);

-- Migrar/Replicar correos existentes desde auth.users a public.perfiles
UPDATE public.perfiles p
SET email = LOWER(TRIM(u.email))
FROM auth.users u
WHERE p.id = u.id AND (p.email IS NULL OR p.email = '');

-- 4. CONFIRMAR AUTOMÁTICAMENTE TODOS LOS CORREOS EXISTENTES Y FUTUROS
-- Evita el bloqueo de 'Email not confirmed' en Supabase para usuarios locales del club
UPDATE auth.users
SET email_confirmed_at = COALESCE(email_confirmed_at, NOW())
WHERE email_confirmed_at IS NULL;

-- Trigger para confirmar automáticamente cualquier nuevo usuario en auth.users
CREATE OR REPLACE FUNCTION public.fn_auto_confirmar_usuario()
RETURNS TRIGGER AS $$
BEGIN
    NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_confirmar_usuario ON auth.users;
CREATE TRIGGER trg_auto_confirmar_usuario
    BEFORE INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.fn_auto_confirmar_usuario();

-- 5. ACTUALIZAR TRIGGER PARA CREACIÓN AUTOMÁTICA DE PERFIL
CREATE OR REPLACE FUNCTION public.fn_handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_total_usuarios INT;
    v_rol_asignado VARCHAR(30);
    v_nombre VARCHAR(150);
    v_telefono VARCHAR(30);
BEGIN
    SELECT COUNT(*) INTO v_total_usuarios FROM public.perfiles;
    
    -- Si se especifica rol en metadata y existe en la tabla roles, usarlo; de lo contrario, admin para el primero y cajero para los siguientes
    v_rol_asignado := COALESCE(
        NEW.raw_user_meta_data->>'rol',
        NEW.raw_user_meta_data->>'role',
        CASE WHEN v_total_usuarios = 0 THEN 'admin' ELSE 'cajero' END
    );

    IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id = v_rol_asignado) THEN
        v_rol_asignado := 'cajero';
    END IF;

    v_nombre := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'nombre',
        SPLIT_PART(NEW.email, '@', 1)
    );

    v_telefono := NEW.raw_user_meta_data->>'telefono';

    INSERT INTO public.perfiles (id, rol_id, nombre_completo, email, telefono, activo, actualizado_en)
    VALUES (NEW.id, v_rol_asignado, v_nombre, LOWER(TRIM(NEW.email)), v_telefono, true, NOW())
    ON CONFLICT (id) DO UPDATE SET
        nombre_completo = COALESCE(EXCLUDED.nombre_completo, public.perfiles.nombre_completo),
        email = COALESCE(EXCLUDED.email, public.perfiles.email),
        telefono = COALESCE(EXCLUDED.telefono, public.perfiles.telefono),
        actualizado_en = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recrear el trigger en auth.users
DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.fn_handle_new_user();

-- 5. PROCEDIMIENTOS ALMACENADOS (RPC) PARA ADMINISTRACIÓN SEGURA DE USUARIOS

-- A) Crear nuevo usuario administrativo directamente sin desloguear al admin
CREATE OR REPLACE FUNCTION public.admin_crear_usuario(
    p_email TEXT,
    p_password TEXT,
    p_nombre TEXT,
    p_rol VARCHAR(30) DEFAULT 'cajero',
    p_telefono TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_encrypted_pw TEXT;
    v_email_clean TEXT;
BEGIN
    v_email_clean := LOWER(TRIM(p_email));

    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email_clean) THEN
        RAISE EXCEPTION 'El correo electrónico ya se encuentra registrado en el sistema.';
    END IF;

    -- Validar que el rol exista
    IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id = p_rol) THEN
        p_rol := 'cajero';
    END IF;

    v_encrypted_pw := crypt(p_password, gen_salt('bf'));
    v_user_id := gen_random_uuid();

    -- Inserción directa en auth.users con confirmación automática
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_user_id,
        'authenticated',
        'authenticated',
        v_email_clean,
        v_encrypted_pw,
        NOW(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', p_nombre, 'nombre', p_nombre, 'rol', p_rol, 'telefono', p_telefono),
        NOW(),
        NOW(),
        '',
        ''
    );

    -- Registrar identidad para que GoTrue permita inicio de sesión inmediato con password
    INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        v_user_id,
        jsonb_build_object('sub', v_user_id::text, 'email', v_email_clean),
        'email',
        NOW(),
        NOW(),
        NOW()
    );

    -- Asegurar perfil sincronizado
    INSERT INTO public.perfiles (id, rol_id, nombre_completo, email, telefono, activo, actualizado_en)
    VALUES (v_user_id, p_rol, p_nombre, v_email_clean, p_telefono, true, NOW())
    ON CONFLICT (id) DO UPDATE SET
        rol_id = EXCLUDED.rol_id,
        nombre_completo = EXCLUDED.nombre_completo,
        email = EXCLUDED.email,
        telefono = EXCLUDED.telefono,
        activo = true,
        actualizado_en = NOW();

    -- Registrar en auditoría
    INSERT INTO public.auditoria (tabla, registro_id, accion, datos_nuevos)
    VALUES (
        'perfiles',
        v_user_id,
        'INSERT',
        jsonb_build_object('email', v_email_clean, 'nombre', p_nombre, 'rol', p_rol, 'accion', 'admin_crear_usuario')
    );

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- B) Actualizar datos de perfil y rol de un usuario
CREATE OR REPLACE FUNCTION public.admin_actualizar_perfil(
    p_usuario_id UUID,
    p_nombre_completo VARCHAR(150),
    p_rol_id VARCHAR(30),
    p_telefono VARCHAR(30),
    p_activo BOOLEAN
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.perfiles
    SET nombre_completo = p_nombre_completo,
        rol_id = p_rol_id,
        telefono = p_telefono,
        activo = p_activo,
        actualizado_en = NOW()
    WHERE id = p_usuario_id;

    -- Actualizar metadata en auth.users
    UPDATE auth.users
    SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
            'full_name', p_nombre_completo,
            'nombre', p_nombre_completo,
            'rol', p_rol_id,
            'telefono', p_telefono
        ),
        updated_at = NOW()
    WHERE id = p_usuario_id;

    -- Auditoría
    INSERT INTO public.auditoria (tabla, registro_id, accion, datos_nuevos)
    VALUES (
        'perfiles',
        p_usuario_id,
        'UPDATE',
        jsonb_build_object('nombre', p_nombre_completo, 'rol', p_rol_id, 'activo', p_activo, 'telefono', p_telefono)
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- C) Cambiar o resetear contraseña de un usuario
CREATE OR REPLACE FUNCTION public.admin_cambiar_password(
    p_usuario_id UUID,
    p_nueva_password TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    IF LENGTH(p_nueva_password) < 6 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 6 caracteres.';
    END IF;

    UPDATE auth.users
    SET encrypted_password = crypt(p_nueva_password, gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_usuario_id;

    -- Auditoría
    INSERT INTO public.auditoria (tabla, registro_id, accion, datos_nuevos)
    VALUES (
        'auth.users',
        p_usuario_id,
        'UPDATE',
        jsonb_build_object('accion', 'admin_cambiar_password')
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- D) Alternar activación / baja lógica de usuario
CREATE OR REPLACE FUNCTION public.admin_alternar_activo(
    p_usuario_id UUID,
    p_activo BOOLEAN
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.perfiles
    SET activo = p_activo,
        actualizado_en = NOW()
    WHERE id = p_usuario_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. POLÍTICAS ROW LEVEL SECURITY (RLS) Y PERMISOS
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lectura de roles para usuarios autenticados" ON public.roles;
DROP POLICY IF EXISTS "Acceso total a roles" ON public.roles;
CREATE POLICY "Acceso total a roles"
    ON public.roles FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Lectura de perfiles para usuarios autenticados" ON public.perfiles;
DROP POLICY IF EXISTS "Usuarios editan su propio perfil" ON public.perfiles;
DROP POLICY IF EXISTS "Admins gestionan perfiles" ON public.perfiles;
DROP POLICY IF EXISTS "Acceso total a perfiles" ON public.perfiles;
CREATE POLICY "Acceso total a perfiles"
    ON public.perfiles FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- Otorgar privilegios de ejecución y acceso
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON public.roles TO anon, authenticated, service_role;
GRANT ALL ON public.perfiles TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.admin_crear_usuario TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_actualizar_perfil TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_cambiar_password TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_alternar_activo TO anon, authenticated, service_role;

-- 7. RECARGAR CACHÉ DE ESQUEMA EN POSTGREST
NOTIFY pgrst, 'reload schema';
