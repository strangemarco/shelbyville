-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 13: Corrección de Zona Horaria (UTC-4 Bolivia) y Expiración de Reservas
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. ACTUALIZAR FUNCIÓN RPC: VERIFICAR Y LIBERAR RESERVAS EXPIRADAS
-- Utiliza la hora local de Bolivia ('America/La_Paz') comparando con la fecha y hora seleccionada
CREATE OR REPLACE FUNCTION public.verificar_y_liberar_reservas_expiradas()
RETURNS INT AS $$
DECLARE
    v_reserva RECORD;
    v_liberadas INT := 0;
    v_ahora_local TIMESTAMP;
BEGIN
    -- Obtener la hora local actual exacta en Bolivia (UTC-4)
    v_ahora_local := NOW() AT TIME ZONE 'America/La_Paz';

    FOR v_reserva IN 
        SELECT r.* FROM public.reservas_mesa r
        WHERE r.estado = 'activa'
          AND (
              -- 1. Expiró porque ya terminó la hora fin programada
              v_ahora_local > (r.fecha + r.hora_fin)
              OR 
              -- 2. Expiró porque pasó el tiempo de tolerancia de llegada tras la hora de inicio
              v_ahora_local > (r.fecha + r.hora_inicio + (COALESCE(r.minutos_tolerancia_llegada, 15) || ' minutes')::INTERVAL)
          )
    LOOP
        -- Marcar la reserva como expirada por inasistencia / tiempo vencido
        UPDATE public.reservas_mesa 
        SET estado = 'expirada' 
        WHERE id = v_reserva.id;

        -- Si la mesa seguía en estado 'reservada' y no tiene otra reserva activa vigente para hoy, liberarla a 'disponible'
        IF NOT EXISTS (
            SELECT 1 FROM public.reservas_mesa 
            WHERE mesa_id = v_reserva.mesa_id 
              AND estado = 'activa' 
              AND id != v_reserva.id
              AND v_ahora_local <= (fecha + hora_fin)
        ) THEN
            UPDATE public.mesas 
            SET estado = 'disponible', actualizado_en = NOW() 
            WHERE id = v_reserva.mesa_id AND estado = 'reservada';
        END IF;

        v_liberadas := v_liberadas + 1;
    END LOOP;

    RETURN v_liberadas;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. ACTUALIZAR FUNCIÓN RPC: CREAR RESERVA DE MESA
-- Calcula y asegura que inicio_utc y fin_utc se conviertan con la zona horaria correcta de Bolivia
CREATE OR REPLACE FUNCTION public.crear_reserva_mesa(
    p_mesa_id UUID,
    p_cliente_nombre VARCHAR,
    p_telefono VARCHAR,
    p_fecha DATE,
    p_hora_inicio TIME,
    p_hora_fin TIME,
    p_inicio_utc TIMESTAMPTZ DEFAULT NULL,
    p_fin_utc TIMESTAMPTZ DEFAULT NULL,
    p_tolerancia_minutos INT DEFAULT 15,
    p_notas TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_reserva_id UUID;
    v_mesa RECORD;
    v_inicio_utc TIMESTAMPTZ;
    v_fin_utc TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_mesa FROM public.mesas WHERE id = p_mesa_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La mesa no existe.';
    END IF;

    IF v_mesa.estado NOT IN ('disponible', 'reservada') THEN
        RAISE EXCEPTION 'La mesa % no está disponible para reservar (Estado actual: %).', v_mesa.numero, v_mesa.estado;
    END IF;

    -- Calcular los timestamps UTC reales a partir de fecha + hora en zona 'America/La_Paz'
    v_inicio_utc := (p_fecha + p_hora_inicio) AT TIME ZONE 'America/La_Paz';
    v_fin_utc := (p_fecha + p_hora_fin) AT TIME ZONE 'America/La_Paz';

    INSERT INTO public.reservas_mesa (
        mesa_id, cliente_nombre, telefono, fecha, hora_inicio, hora_fin,
        inicio_utc, fin_utc, minutos_tolerancia_llegada, estado, notas
    ) VALUES (
        p_mesa_id, p_cliente_nombre, p_telefono, p_fecha, p_hora_inicio, p_hora_fin,
        v_inicio_utc, v_fin_utc, COALESCE(p_tolerancia_minutos, 15), 'activa', p_notas
    ) RETURNING id INTO v_reserva_id;

    -- Actualizar estado de la mesa a 'reservada'
    UPDATE public.mesas SET estado = 'reservada', actualizado_en = NOW() WHERE id = p_mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'reserva_id', v_reserva_id,
        'mensaje', 'Reserva registrada con éxito.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. PERMISOS DE EJECUCIÓN RPC
GRANT EXECUTE ON FUNCTION public.verificar_y_liberar_reservas_expiradas TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crear_reserva_mesa TO anon, authenticated, service_role;

-- 4. REACTIVAR RESERVAS ERRÓNEAMENTE EXPIRADAS DEL DÍA DE HOY
-- Si una reserva para hoy fue marcada como expirada antes de su hora o tolerancia, restaurarla
UPDATE public.reservas_mesa 
SET estado = 'activa' 
WHERE estado = 'expirada' 
  AND (fecha + hora_fin) > (NOW() AT TIME ZONE 'America/La_Paz')
  AND (fecha + hora_inicio + (COALESCE(minutos_tolerancia_llegada, 15) || ' minutes')::INTERVAL) > (NOW() AT TIME ZONE 'America/La_Paz');

-- Actualizar mesas a 'reservada' para las reservas activas
UPDATE public.mesas 
SET estado = 'reservada', actualizado_en = NOW()
WHERE id IN (
    SELECT mesa_id FROM public.reservas_mesa 
    WHERE estado = 'activa' 
      AND (fecha + hora_fin) > (NOW() AT TIME ZONE 'America/La_Paz')
) AND estado = 'disponible';

-- 5. REFRESCAR CACHÉ DE ESQUEMA EN SUPABASE POSTGREST
NOTIFY pgrst, 'reload schema';
