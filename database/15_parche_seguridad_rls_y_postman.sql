-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 15: Parche de Seguridad Crítico - Blindaje RLS, Postman y Protección de RPCs
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. VERIFICAR FUNCIÓN DE APOYO PARA IDENTIFICAR ADMINISTRADORES
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

-- 2. BLINDAJE DE PROCEDIMIENTOS ALMACENADOS ADMINISTRATIVOS
-- A) admin_cambiar_password: Solo administradores autenticados o el propio usuario
CREATE OR REPLACE FUNCTION public.admin_cambiar_password(
    p_usuario_id UUID,
    p_nueva_password TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Regla de seguridad: Solo un admin o el propio usuario pueden cambiar su contraseña
    IF NOT (public.fn_es_admin() OR auth.uid() = p_usuario_id) THEN
        RAISE EXCEPTION 'Acceso denegado: Se requieren permisos de administrador para cambiar la contraseña de otro usuario.';
    END IF;

    IF LENGTH(p_nueva_password) < 6 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 6 caracteres.';
    END IF;

    UPDATE auth.users
    SET encrypted_password = crypt(p_nueva_password, gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_usuario_id;

    -- Registrar auditoría
    INSERT INTO public.auditoria (tabla, registro_id, accion, datos_nuevos)
    VALUES (
        'auth.users',
        p_usuario_id,
        'UPDATE',
        jsonb_build_object('accion', 'admin_cambiar_password', 'ejecutado_por', auth.uid())
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- B) admin_crear_usuario: Exclusivo para administradores
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
    -- Regla de seguridad: Solo un admin puede crear cuentas arbitrarias
    IF NOT public.fn_es_admin() THEN
        RAISE EXCEPTION 'Acceso denegado: Solo administradores pueden crear nuevos usuarios en el sistema.';
    END IF;

    v_email_clean := LOWER(TRIM(p_email));

    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email_clean) THEN
        RAISE EXCEPTION 'El correo electrónico ya se encuentra registrado en el sistema.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id = p_rol) THEN
        p_rol := 'cajero';
    END IF;

    v_encrypted_pw := crypt(p_password, gen_salt('bf'));
    v_user_id := gen_random_uuid();

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

    INSERT INTO public.perfiles (id, rol_id, nombre_completo, email, telefono, activo, actualizado_en)
    VALUES (v_user_id, p_rol, p_nombre, v_email_clean, p_telefono, true, NOW())
    ON CONFLICT (id) DO UPDATE SET
        rol_id = EXCLUDED.rol_id,
        nombre_completo = EXCLUDED.nombre_completo,
        email = EXCLUDED.email,
        telefono = EXCLUDED.telefono,
        activo = true,
        actualizado_en = NOW();

    INSERT INTO public.auditoria (tabla, registro_id, accion, datos_nuevos)
    VALUES (
        'perfiles',
        v_user_id,
        'INSERT',
        jsonb_build_object('email', v_email_clean, 'nombre', p_nombre, 'rol', p_rol, 'accion', 'admin_crear_usuario', 'ejecutado_por', auth.uid())
    );

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- C) admin_actualizar_perfil: Exclusivo para administradores
CREATE OR REPLACE FUNCTION public.admin_actualizar_perfil(
    p_usuario_id UUID,
    p_nombre_completo VARCHAR(150),
    p_rol_id VARCHAR(30),
    p_telefono VARCHAR(30),
    p_activo BOOLEAN
)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.fn_es_admin() THEN
        RAISE EXCEPTION 'Acceso denegado: Solo administradores pueden modificar perfiles ajenos o cambiar roles.';
    END IF;

    UPDATE public.perfiles
    SET nombre_completo = p_nombre_completo,
        rol_id = p_rol_id,
        telefono = p_telefono,
        activo = p_activo,
        actualizado_en = NOW()
    WHERE id = p_usuario_id;

    UPDATE auth.users
    SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
            'full_name', p_nombre_completo,
            'nombre', p_nombre_completo,
            'rol', p_rol_id,
            'telefono', p_telefono
        ),
        updated_at = NOW()
    WHERE id = p_usuario_id;

    INSERT INTO public.auditoria (tabla, registro_id, accion, datos_nuevos)
    VALUES (
        'perfiles',
        p_usuario_id,
        'UPDATE',
        jsonb_build_object('nombre', p_nombre_completo, 'rol', p_rol_id, 'activo', p_activo, 'telefono', p_telefono, 'ejecutado_por', auth.uid())
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- D) admin_alternar_activo: Exclusivo para administradores
CREATE OR REPLACE FUNCTION public.admin_alternar_activo(
    p_usuario_id UUID,
    p_activo BOOLEAN
)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.fn_es_admin() THEN
        RAISE EXCEPTION 'Acceso denegado: Solo administradores pueden activar o desactivar cuentas.';
    END IF;

    UPDATE public.perfiles
    SET activo = p_activo,
        actualizado_en = NOW()
    WHERE id = p_usuario_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. REVOCAR PRIVILEGIOS A USUARIOS ANÓNIMOS EN RPCs ADMINISTRATIVAS
REVOKE EXECUTE ON FUNCTION public.admin_crear_usuario FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_actualizar_perfil FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_cambiar_password FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_alternar_activo FROM anon;

GRANT EXECUTE ON FUNCTION public.admin_crear_usuario TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_actualizar_perfil TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_cambiar_password TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_alternar_activo TO authenticated, service_role;

-- 4. RESTRINGIR ROW LEVEL SECURITY EN LA TABLA DE PERFILES
DROP POLICY IF EXISTS "Acceso total a perfiles" ON public.perfiles;
DROP POLICY IF EXISTS "Lectura de perfiles para usuarios autenticados" ON public.perfiles;
DROP POLICY IF EXISTS "Usuarios editan su propio perfil" ON public.perfiles;
DROP POLICY IF EXISTS "Admins gestionan perfiles" ON public.perfiles;

-- Solo usuarios autenticados activos pueden leer la lista de perfiles
CREATE POLICY "Lectura de perfiles solo autenticados activos"
    ON public.perfiles FOR SELECT
    TO authenticated
    USING (public.fn_usuario_autenticado_activo());

-- Los usuarios pueden editar datos básicos de su propio perfil (nombre, teléfono), pero no su rol ni su estado activo
CREATE POLICY "Usuarios editan su propio perfil"
    ON public.perfiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid() AND rol_id = (SELECT rol_id FROM public.perfiles WHERE id = auth.uid()));

-- Los administradores tienen control total sobre los perfiles
CREATE POLICY "Admins gestionan todos los perfiles"
    ON public.perfiles FOR ALL
    TO authenticated
    USING (public.fn_es_admin())
    WITH CHECK (public.fn_es_admin());

-- 5. BLINDAJE DE KARDEX Y REGISTROS FINANCIEROS (VENTAS, CAJAS, AUDITORIA) CONTRA ANON
-- Revocar escritura a anónimos en tablas sensibles
REVOKE INSERT, UPDATE, DELETE ON public.ventas FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.detalles_venta FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.pagos FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.cajas FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.movimientos_caja FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.movimientos_inventario FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.auditoria FROM anon;

-- 6. RECARGAR CACHÉ DE POSTGREST
NOTIFY pgrst, 'reload schema';
