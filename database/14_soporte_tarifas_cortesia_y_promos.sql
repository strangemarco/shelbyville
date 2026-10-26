-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 14: Soporte de Tarifas con Minutos de Cortesía / Promociones (ej. Promo Cumpleañero)
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. AGREGAR COLUMNA DE MINUTOS DE CORTESÍA A LA TABLA TARIFAS
ALTER TABLE public.tarifas 
ADD COLUMN IF NOT EXISTS minutos_cortesia INT NOT NULL DEFAULT 0;

-- 2. ACTUALIZAR FUNCIÓN: CALCULAR TIEMPO Y MONTO DE SESIÓN (CONSIDERANDO CORTESÍA)
CREATE OR REPLACE FUNCTION public.calcular_tiempo_y_monto_sesion(
    p_sesion_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
    v_tarifa RECORD;
    v_ahora TIMESTAMPTZ := NOW();
    v_hora_corte TIMESTAMPTZ;
    v_segundos_brutos INT;
    v_segundos_netos INT;
    v_minutos_transcurridos INT;
    v_minutos_cortesia INT := 0;
    v_minutos_efectivos INT := 0;
    v_minutos_cobrables INT := 0;
    v_monto_tiempo NUMERIC(10,2) := 0.00;
    v_pausa_activa RECORD;
    v_segundos_pausa_actual INT := 0;
BEGIN
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    SELECT * INTO v_tarifa FROM public.tarifas WHERE id = v_sesion.tarifa_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La tarifa asociada no existe.';
    END IF;

    -- Si la sesión ya tiene hora_fin, usar esa hora, sino NOW()
    v_hora_corte := COALESCE(v_sesion.hora_fin, v_ahora);

    -- Si está pausada actualmente, computar los segundos de la pausa en curso
    IF v_sesion.estado = 'pausada' THEN
        SELECT * INTO v_pausa_activa FROM public.pausas_sesion 
        WHERE sesion_id = p_sesion_id AND hora_fin IS NULL 
        ORDER BY hora_inicio DESC LIMIT 1;
        IF FOUND THEN
            v_segundos_pausa_actual := EXTRACT(EPOCH FROM (v_hora_corte - v_pausa_activa.hora_inicio))::INT;
        END IF;
    END IF;

    v_segundos_brutos := EXTRACT(EPOCH FROM (v_hora_corte - v_sesion.hora_inicio))::INT;
    v_segundos_netos := GREATEST(0, v_segundos_brutos - (v_sesion.segundos_pausados + v_segundos_pausa_actual));
    v_minutos_transcurridos := CEIL(v_segundos_netos / 60.0);

    -- Minutos de cortesía configurados en la tarifa (ej. 60 min para Promo Cumpleañero)
    v_minutos_cortesia := COALESCE(v_tarifa.minutos_cortesia, 0);

    -- Minutos que sobrepasan el tiempo de cortesía / regalo
    v_minutos_efectivos := GREATEST(0, v_minutos_transcurridos - v_minutos_cortesia);

    -- Si no ha superado la cortesía o está dentro de la tolerancia de gracia posterior
    IF v_minutos_efectivos <= v_tarifa.minutos_tolerancia THEN
        v_minutos_cobrables := 0;
    ELSIF v_minutos_efectivos < v_tarifa.minutos_minimo THEN
        v_minutos_cobrables := v_tarifa.minutos_minimo;
    ELSE
        v_minutos_cobrables := v_minutos_efectivos;
    END IF;

    v_monto_tiempo := ROUND((v_minutos_cobrables * (v_tarifa.precio_por_hora / 60.0)), 2);

    RETURN jsonb_build_object(
        'sesion_id', p_sesion_id,
        'segundos_netos', v_segundos_netos,
        'minutos_transcurridos', v_minutos_transcurridos,
        'minutos_cortesia', v_minutos_cortesia,
        'minutos_cobrables', v_minutos_cobrables,
        'monto_tiempo', v_monto_tiempo,
        'monto_consumos', v_sesion.monto_consumos,
        'monto_total', ROUND(v_monto_tiempo + v_sesion.monto_consumos - v_sesion.monto_descuento, 2)
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. INSERTAR TARIFA PRECONFIGURADA: PROMO CUMPLEAÑERO (1 HORA GRATIS)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tarifas WHERE nombre ILIKE '%cumplea%') THEN
        INSERT INTO public.tarifas (
            nombre,
            descripcion,
            precio_por_hora,
            minutos_minimo,
            minutos_tolerancia,
            minutos_cortesia,
            activo
        ) VALUES (
            'Promo Cumpleañero (1h Gratis)',
            '1 hora de cortesía presentando Carnet de Identidad. A partir del minuto 61 rige la tarifa normal.',
            25.00,
            15,
            5,
            60,
            true
        );
    ELSE
        -- Si ya existía, asegurarse de que tenga minutos_cortesia = 60
        UPDATE public.tarifas 
        SET minutos_cortesia = 60 
        WHERE nombre ILIKE '%cumplea%';
    END IF;
END $$;

-- 4. PERMISOS
GRANT EXECUTE ON FUNCTION public.calcular_tiempo_y_monto_sesion(UUID) TO anon, authenticated, service_role;

-- 5. RECARGAR ESQUEMA SUPABASE
NOTIFY pgrst, 'reload schema';
