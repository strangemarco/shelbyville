-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 09: Gestión de Mesas, Tarifas y Reservas con Auto-Expiración
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. ACTUALIZAR RESTRICCIÓN DE ESTADOS EN MESAS PARA PERMITIR 'reservada'
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT conname 
        FROM pg_constraint 
        WHERE conrelid = 'public.mesas'::regclass 
          AND contype = 'c'
          AND pg_get_constraintdef(oid) LIKE '%estado%'
    ) LOOP
        EXECUTE 'ALTER TABLE public.mesas DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
    END LOOP;
END $$;

ALTER TABLE public.mesas ADD CONSTRAINT mesas_estado_check 
    CHECK (estado IN ('disponible', 'ocupada', 'pausada', 'mantenimiento', 'reservada'));

-- 2. TABLA DE RESERVAS DE MESAS
CREATE TABLE IF NOT EXISTS public.reservas_mesa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mesa_id UUID NOT NULL REFERENCES public.mesas(id) ON DELETE CASCADE,
    cliente_nombre VARCHAR(120) NOT NULL,
    telefono VARCHAR(50),
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    inicio_utc TIMESTAMPTZ NOT NULL,
    fin_utc TIMESTAMPTZ NOT NULL,
    minutos_tolerancia_llegada INT NOT NULL DEFAULT 15,
    estado VARCHAR(30) NOT NULL DEFAULT 'activa' CHECK (estado IN ('activa', 'completada', 'cancelada', 'expirada')),
    notas TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. PERMISOS Y RLS PARA RESERVAS
ALTER TABLE public.reservas_mesa ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Acceso total a reservas" ON public.reservas_mesa;
CREATE POLICY "Acceso total a reservas"
    ON public.reservas_mesa FOR ALL
    TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

GRANT ALL ON public.reservas_mesa TO anon, authenticated, service_role;

-- 4. FUNCION RPC: VERIFICAR Y LIBERAR RESERVAS EXPIRADAS
CREATE OR REPLACE FUNCTION public.verificar_y_liberar_reservas_expiradas()
RETURNS INT AS $$
DECLARE
    v_reserva RECORD;
    v_liberadas INT := 0;
BEGIN
    FOR v_reserva IN 
        SELECT r.* FROM public.reservas_mesa r
        WHERE r.estado = 'activa'
          AND (NOW() > r.fin_utc OR NOW() > (r.inicio_utc + (r.minutos_tolerancia_llegada || ' minutes')::INTERVAL))
    LOOP
        -- Marcar reserva como expirada
        UPDATE public.reservas_mesa 
        SET estado = 'expirada' 
        WHERE id = v_reserva.id;

        -- Si la mesa seguía reservada, liberarla inmediatamente
        UPDATE public.mesas 
        SET estado = 'disponible', actualizado_en = NOW() 
        WHERE id = v_reserva.mesa_id AND estado = 'reservada';

        v_liberadas := v_liberadas + 1;
    END LOOP;

    RETURN v_liberadas;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. FUNCION RPC: CREAR RESERVA DE MESA
CREATE OR REPLACE FUNCTION public.crear_reserva_mesa(
    p_mesa_id UUID,
    p_cliente_nombre VARCHAR,
    p_telefono VARCHAR,
    p_fecha DATE,
    p_hora_inicio TIME,
    p_hora_fin TIME,
    p_inicio_utc TIMESTAMPTZ,
    p_fin_utc TIMESTAMPTZ,
    p_tolerancia_minutos INT DEFAULT 15,
    p_notas TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_reserva_id UUID;
    v_mesa RECORD;
BEGIN
    SELECT * INTO v_mesa FROM public.mesas WHERE id = p_mesa_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La mesa no existe.';
    END IF;

    IF v_mesa.estado NOT IN ('disponible', 'reservada') THEN
        RAISE EXCEPTION 'La mesa % no está disponible para reservar (Estado actual: %).', v_mesa.numero, v_mesa.estado;
    END IF;

    INSERT INTO public.reservas_mesa (
        mesa_id, cliente_nombre, telefono, fecha, hora_inicio, hora_fin,
        inicio_utc, fin_utc, minutos_tolerancia_llegada, estado, notas
    ) VALUES (
        p_mesa_id, p_cliente_nombre, p_telefono, p_fecha, p_hora_inicio, p_hora_fin,
        p_inicio_utc, p_fin_utc, COALESCE(p_tolerancia_minutos, 15), 'activa', p_notas
    ) RETURNING id INTO v_reserva_id;

    -- Poner la mesa en estado 'reservada'
    UPDATE public.mesas SET estado = 'reservada', actualizado_en = NOW() WHERE id = p_mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'reserva_id', v_reserva_id,
        'mensaje', 'Reserva registrada con éxito.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. FUNCION RPC: CANCELAR O LIBERAR RESERVA
CREATE OR REPLACE FUNCTION public.cancelar_reserva_mesa(
    p_reserva_id UUID,
    p_motivo TEXT DEFAULT 'Cancelada por el operador'
)
RETURNS JSONB AS $$
DECLARE
    v_reserva RECORD;
BEGIN
    SELECT * INTO v_reserva FROM public.reservas_mesa WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La reserva no existe.';
    END IF;

    UPDATE public.reservas_mesa 
    SET estado = 'cancelada', notas = COALESCE(notas, '') || ' [Cancelada: ' || p_motivo || ']'
    WHERE id = p_reserva_id;

    UPDATE public.mesas 
    SET estado = 'disponible', actualizado_en = NOW() 
    WHERE id = v_reserva.mesa_id AND estado = 'reservada';

    RETURN jsonb_build_object(
        'success', true,
        'mensaje', 'Reserva cancelada y mesa liberada.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. ACTUALIZAR iniciar_sesion_mesa PARA PERMITIR MESAS RESERVADAS
CREATE OR REPLACE FUNCTION public.iniciar_sesion_mesa(
    p_mesa_id UUID,
    p_tarifa_id UUID DEFAULT NULL,
    p_cliente_nombre VARCHAR DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_mesa RECORD;
    v_tarifa_id UUID;
    v_sesion_id UUID;
    v_sesion_activa RECORD;
BEGIN
    SELECT * INTO v_mesa FROM public.mesas WHERE id = p_mesa_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La mesa especificada no existe.';
    END IF;

    -- Permite iniciar sesión si la mesa está disponible o reservada
    IF v_mesa.estado NOT IN ('disponible', 'reservada') THEN
        RAISE EXCEPTION 'La mesa % no está disponible (Estado actual: %).', v_mesa.numero, v_mesa.estado;
    END IF;

    SELECT * INTO v_sesion_activa FROM public.sesiones_billar 
    WHERE mesa_id = p_mesa_id AND estado IN ('activa', 'pausada', 'pendiente_pago');
    IF FOUND THEN
        RAISE EXCEPTION 'La mesa % ya tiene una sesión en curso.', v_mesa.numero;
    END IF;

    v_tarifa_id := p_tarifa_id;
    IF v_tarifa_id IS NULL THEN
        v_tarifa_id := v_mesa.tarifa_defecto_id;
    END IF;
    IF v_tarifa_id IS NULL THEN
        SELECT id INTO v_tarifa_id FROM public.tarifas WHERE activo = true LIMIT 1;
    END IF;
    IF v_tarifa_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró una tarifa válida configurada.';
    END IF;

    INSERT INTO public.sesiones_billar (
        mesa_id,
        tarifa_id,
        cliente_nombre,
        hora_inicio,
        estado,
        usuario_inicio_id
    ) VALUES (
        p_mesa_id,
        v_tarifa_id,
        COALESCE(p_cliente_nombre, 'Cliente Mostrador'),
        NOW(),
        'activa',
        p_usuario_id
    ) RETURNING id INTO v_sesion_id;

    UPDATE public.mesas SET estado = 'ocupada', actualizado_en = NOW() WHERE id = p_mesa_id;

    -- Si tenía una reserva activa, completarla
    UPDATE public.reservas_mesa 
    SET estado = 'completada' 
    WHERE mesa_id = p_mesa_id AND estado = 'activa';

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', v_sesion_id,
        'mesa_id', p_mesa_id,
        'mensaje', 'Sesión iniciada exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. PERMISOS DE EJECUCIÓN RPC
GRANT EXECUTE ON FUNCTION public.verificar_y_liberar_reservas_expiradas TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crear_reserva_mesa TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancelar_reserva_mesa TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iniciar_sesion_mesa TO anon, authenticated, service_role;

-- 9. SUSCRIPCION A REALTIME
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'reservas_mesa'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.reservas_mesa;
    END IF;
END $$;

-- 10. REFRESCAR CACHÉ DE ESQUEMA EN SUPABASE POSTGREST
NOTIFY pgrst, 'reload schema';
