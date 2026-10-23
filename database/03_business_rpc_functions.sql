-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 03: Funciones del Negocio (RPC)
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. FUNCION: INICIAR SESION DE BILLAR
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
    -- Validar existencia de mesa
    SELECT * INTO v_mesa FROM public.mesas WHERE id = p_mesa_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La mesa especificada no existe.';
    END IF;

    IF v_mesa.estado <> 'disponible' THEN
        RAISE EXCEPTION 'La mesa % no está disponible (Estado actual: %).', v_mesa.numero, v_mesa.estado;
    END IF;

    -- Validar que no haya una sesión activa previa
    SELECT * INTO v_sesion_activa FROM public.sesiones_billar 
    WHERE mesa_id = p_mesa_id AND estado IN ('activa', 'pausada', 'pendiente_pago');
    IF FOUND THEN
        RAISE EXCEPTION 'La mesa % ya tiene una sesión en curso.', v_mesa.numero;
    END IF;

    -- Obtener tarifa (si es NULL, usar la tarifa por defecto de la mesa o la primera activa)
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

    -- Insertar sesión
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

    -- Actualizar estado de mesa
    UPDATE public.mesas
    SET estado = 'ocupada'
    WHERE id = p_mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', v_sesion_id,
        'mesa_id', p_mesa_id,
        'mensaje', 'Sesión iniciada exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. FUNCION: PAUSAR SESION
CREATE OR REPLACE FUNCTION public.pausar_sesion_mesa(
    p_sesion_id UUID,
    p_motivo VARCHAR DEFAULT 'Pausa solicitada'
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
BEGIN
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    IF v_sesion.estado <> 'activa' THEN
        RAISE EXCEPTION 'La sesión no se encuentra en estado activa (Estado: %).', v_sesion.estado;
    END IF;

    -- Crear registro de pausa
    INSERT INTO public.pausas_sesion (sesion_id, hora_inicio, motivo)
    VALUES (p_sesion_id, NOW(), p_motivo);

    -- Actualizar estados
    UPDATE public.sesiones_billar SET estado = 'pausada' WHERE id = p_sesion_id;
    UPDATE public.mesas SET estado = 'pausada' WHERE id = v_sesion.mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', p_sesion_id,
        'mensaje', 'Sesión pausada exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. FUNCION: REANUDAR SESION
CREATE OR REPLACE FUNCTION public.reanudar_sesion_mesa(
    p_sesion_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
    v_pausa RECORD;
    v_duracion_segundos INT;
BEGIN
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    IF v_sesion.estado <> 'pausada' THEN
        RAISE EXCEPTION 'La sesión no se encuentra en pausa (Estado: %).', v_sesion.estado;
    END IF;

    -- Buscar última pausa abierta
    SELECT * INTO v_pausa FROM public.pausas_sesion 
    WHERE sesion_id = p_sesion_id AND hora_fin IS NULL 
    ORDER BY hora_inicio DESC LIMIT 1 FOR UPDATE;

    IF FOUND THEN
        v_duracion_segundos := EXTRACT(EPOCH FROM (NOW() - v_pausa.hora_inicio))::INT;
        UPDATE public.pausas_sesion 
        SET hora_fin = NOW(), duracion_segundos = v_duracion_segundos 
        WHERE id = v_pausa.id;
    ELSE
        v_duracion_segundos := 0;
    END IF;

    -- Actualizar acumulado de pausas en la sesión
    UPDATE public.sesiones_billar 
    SET estado = 'activa',
        segundos_pausados = segundos_pausados + COALESCE(v_duracion_segundos, 0)
    WHERE id = p_sesion_id;

    -- Actualizar mesa a ocupada
    UPDATE public.mesas SET estado = 'ocupada' WHERE id = v_sesion.mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', p_sesion_id,
        'segundos_pausados_agregados', v_duracion_segundos,
        'mensaje', 'Sesión reanudada con éxito.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. FUNCION: CAMBIAR MESA DE UNA SESION ACTIVA
CREATE OR REPLACE FUNCTION public.cambiar_mesa_sesion(
    p_sesion_id UUID,
    p_nueva_mesa_id UUID,
    p_motivo TEXT DEFAULT 'Cambio de mesa solicitado por el cliente'
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
    v_mesa_origen RECORD;
    v_mesa_destino RECORD;
BEGIN
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    IF v_sesion.estado NOT IN ('activa', 'pausada') THEN
        RAISE EXCEPTION 'Solo se pueden transferir sesiones activas o pausadas.';
    END IF;

    SELECT * INTO v_mesa_origen FROM public.mesas WHERE id = v_sesion.mesa_id FOR UPDATE;
    SELECT * INTO v_mesa_destino FROM public.mesas WHERE id = p_nueva_mesa_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La mesa destino no existe.';
    END IF;

    IF v_mesa_destino.estado <> 'disponible' THEN
        RAISE EXCEPTION 'La mesa destino (Mesa %) no está disponible.', v_mesa_destino.numero;
    END IF;

    -- Liberar mesa origen
    UPDATE public.mesas SET estado = 'disponible' WHERE id = v_mesa_origen.id;

    -- Asignar nuevo estado a mesa destino según estado de la sesión
    UPDATE public.mesas SET estado = v_mesa_origen.estado WHERE id = v_mesa_destino.id;

    -- Actualizar sesión
    UPDATE public.sesiones_billar 
    SET mesa_id = p_nueva_mesa_id,
        notas = COALESCE(notas, '') || E'\n' || '[Cambio de Mesa ' || v_mesa_origen.numero || ' a Mesa ' || v_mesa_destino.numero || ': ' || p_motivo || ']'
    WHERE id = p_sesion_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', p_sesion_id,
        'mesa_anterior', v_mesa_origen.numero,
        'mesa_nueva', v_mesa_destino.numero,
        'mensaje', 'Mesa cambiada exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. FUNCION: CALCULAR TIEMPO Y MONTO COBRABLE
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
    v_minutos_cobrables INT;
    v_monto_tiempo NUMERIC(10,2);
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

    -- Aplicar reglas de tarifa:
    -- 1. Si los minutos transcurridos son menores al tiempo de tolerancia inicial, podría considerarse 0 si aplica, o el mínimo.
    -- Generalmente: mínimo facturable aplica si jugó más que la tolerancia.
    IF v_minutos_transcurridos <= v_tarifa.minutos_tolerancia THEN
        v_minutos_cobrables := 0;
    ELSIF v_minutos_transcurridos < v_tarifa.minutos_minimo THEN
        v_minutos_cobrables := v_tarifa.minutos_minimo;
    ELSE
        -- Redondeo por minuto exacto según tarifa por hora
        v_minutos_cobrables := v_minutos_transcurridos;
    END IF;

    v_monto_tiempo := ROUND((v_minutos_cobrables * (v_tarifa.precio_por_hora / 60.0)), 2);

    RETURN jsonb_build_object(
        'sesion_id', p_sesion_id,
        'segundos_netos', v_segundos_netos,
        'minutos_transcurridos', v_minutos_transcurridos,
        'minutos_cobrables', v_minutos_cobrables,
        'monto_tiempo', v_monto_tiempo,
        'monto_consumos', v_sesion.monto_consumos,
        'monto_total', ROUND(v_monto_tiempo + v_sesion.monto_consumos - v_sesion.monto_descuento, 2)
    );
END;
$$ LANGUAGE plpgsql STABLE;


-- 6. FUNCION: AGREGAR CONSUMO A MESA CON CONTROL ATOMICO DE STOCK
CREATE OR REPLACE FUNCTION public.agregar_consumo_mesa(
    p_sesion_id UUID,
    p_producto_id UUID,
    p_cantidad INT,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
    v_producto RECORD;
    v_subtotal NUMERIC(10,2);
    v_consumo_id UUID;
    v_nuevo_stock INT;
    v_calculo JSONB;
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a cero.';
    END IF;

    -- Validar sesión activa
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    IF v_sesion.estado NOT IN ('activa', 'pausada') THEN
        RAISE EXCEPTION 'No se pueden agregar consumos a una sesión en estado %.', v_sesion.estado;
    END IF;

    -- Validar producto y stock con bloqueo de fila
    SELECT * INTO v_producto FROM public.productos WHERE id = p_producto_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto no existe.';
    END IF;

    IF NOT v_producto.activo THEN
        RAISE EXCEPTION 'El producto % no está activo para venta.', v_producto.nombre;
    END IF;

    IF v_producto.stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para %. Disponible: %, Solicitado: %', 
            v_producto.nombre, v_producto.stock, p_cantidad;
    END IF;

    -- Descontar stock
    v_nuevo_stock := v_producto.stock - p_cantidad;
    UPDATE public.productos SET stock = v_nuevo_stock WHERE id = p_producto_id;

    -- Registrar movimiento en KARDEX
    INSERT INTO public.movimientos_inventario (
        producto_id,
        tipo,
        cantidad,
        stock_anterior,
        stock_nuevo,
        referencia_id,
        motivo,
        usuario_id
    ) VALUES (
        p_producto_id,
        'consumo_mesa',
        -p_cantidad,
        v_producto.stock,
        v_nuevo_stock,
        p_sesion_id,
        'Consumo cargado a mesa (Sesión: ' || p_sesion_id || ')',
        p_usuario_id
    );

    -- Insertar consumo
    v_subtotal := ROUND(p_cantidad * v_producto.precio_venta, 2);
    INSERT INTO public.consumos_mesa (
        sesion_id,
        producto_id,
        cantidad,
        precio_unitario,
        subtotal,
        estado,
        usuario_id
    ) VALUES (
        p_sesion_id,
        p_producto_id,
        p_cantidad,
        v_producto.precio_venta,
        v_subtotal,
        'confirmado',
        p_usuario_id
    ) RETURNING id INTO v_consumo_id;

    -- Actualizar acumulado de consumos en la sesión
    UPDATE public.sesiones_billar
    SET monto_consumos = monto_consumos + v_subtotal
    WHERE id = p_sesion_id;

    -- Recalcular total actualizado
    v_calculo := public.calcular_tiempo_y_monto_sesion(p_sesion_id);
    UPDATE public.sesiones_billar
    SET monto_total = (v_calculo->>'monto_total')::NUMERIC
    WHERE id = p_sesion_id;

    RETURN jsonb_build_object(
        'success', true,
        'consumo_id', v_consumo_id,
        'subtotal', v_subtotal,
        'stock_restante', v_nuevo_stock,
        'mensaje', 'Consumo agregado exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 7. FUNCION: ANULAR CONSUMO Y RESTITUIR STOCK
CREATE OR REPLACE FUNCTION public.anular_consumo_mesa(
    p_consumo_id UUID,
    p_motivo TEXT,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_consumo RECORD;
    v_producto RECORD;
    v_nuevo_stock INT;
    v_calculo JSONB;
BEGIN
    SELECT * INTO v_consumo FROM public.consumos_mesa WHERE id = p_consumo_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El consumo no existe.';
    END IF;

    IF v_consumo.estado = 'anulado' THEN
        RAISE EXCEPTION 'Este consumo ya fue anulado previamente.';
    END IF;

    -- Devolver stock al producto
    SELECT * INTO v_producto FROM public.productos WHERE id = v_consumo.producto_id FOR UPDATE;
    v_nuevo_stock := v_producto.stock + v_consumo.cantidad;
    UPDATE public.productos SET stock = v_nuevo_stock WHERE id = v_producto.id;

    -- Registrar movimiento compensatorio en KARDEX
    INSERT INTO public.movimientos_inventario (
        producto_id,
        tipo,
        cantidad,
        stock_anterior,
        stock_nuevo,
        referencia_id,
        motivo,
        usuario_id
    ) VALUES (
        v_producto.id,
        'anulacion',
        v_consumo.cantidad,
        v_producto.stock,
        v_nuevo_stock,
        v_consumo.sesion_id,
        'Anulación de consumo: ' || p_motivo,
        p_usuario_id
    );

    -- Marcar consumo como anulado
    UPDATE public.consumos_mesa 
    SET estado = 'anulado', motivo_anulacion = p_motivo 
    WHERE id = p_consumo_id;

    -- Restar de la sesión
    UPDATE public.sesiones_billar 
    SET monto_consumos = GREATEST(0, monto_consumos - v_consumo.subtotal) 
    WHERE id = v_consumo.sesion_id;

    -- Recalcular total
    v_calculo := public.calcular_tiempo_y_monto_sesion(v_consumo.sesion_id);
    UPDATE public.sesiones_billar 
    SET monto_total = (v_calculo->>'monto_total')::NUMERIC 
    WHERE id = v_consumo.sesion_id;

    RETURN jsonb_build_object(
        'success', true,
        'consumo_id', p_consumo_id,
        'stock_actualizado', v_nuevo_stock,
        'mensaje', 'Consumo anulado y stock restituido.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 8. FUNCION: FINALIZAR TIEMPO DE JUEGO (DETIENE CRONOMETRO)
CREATE OR REPLACE FUNCTION public.finalizar_sesion_mesa(
    p_sesion_id UUID,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
    v_calculo JSONB;
BEGIN
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    IF v_sesion.estado NOT IN ('activa', 'pausada') THEN
        RAISE EXCEPTION 'La sesión no está activa ni pausada (Estado actual: %).', v_sesion.estado;
    END IF;

    -- Si estaba pausada, cerrar la pausa abierta
    IF v_sesion.estado = 'pausada' THEN
        UPDATE public.pausas_sesion 
        SET hora_fin = NOW(),
            duracion_segundos = EXTRACT(EPOCH FROM (NOW() - hora_inicio))::INT
        WHERE sesion_id = p_sesion_id AND hora_fin IS NULL;
    END IF;

    -- Establecer hora_fin
    UPDATE public.sesiones_billar
    SET hora_fin = NOW(),
        estado = 'pendiente_pago',
        usuario_cierre_id = p_usuario_id
    WHERE id = p_sesion_id;

    -- Calcular montos finales congelados
    v_calculo := public.calcular_tiempo_y_monto_sesion(p_sesion_id);

    UPDATE public.sesiones_billar
    SET minutos_cobrables = (v_calculo->>'minutos_cobrables')::INT,
        monto_tiempo = (v_calculo->>'monto_tiempo')::NUMERIC,
        monto_total = (v_calculo->>'monto_total')::NUMERIC
    WHERE id = p_sesion_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', p_sesion_id,
        'minutos_cobrables', (v_calculo->>'minutos_cobrables')::INT,
        'monto_tiempo', (v_calculo->>'monto_tiempo')::NUMERIC,
        'monto_consumos', v_sesion.monto_consumos,
        'monto_total', (v_calculo->>'monto_total')::NUMERIC,
        'mensaje', 'Tiempo detenido. Cuenta lista para cobrar.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 9. FUNCION: LIQUIDAR Y COBRAR SESION DE BILLAR (LIBERA LA MESA)
DROP FUNCTION IF EXISTS public.liquidar_sesion_mesa(UUID, UUID, VARCHAR, NUMERIC, NUMERIC, VARCHAR, UUID);

CREATE OR REPLACE FUNCTION public.liquidar_sesion_mesa(
    p_sesion_id UUID,
    p_caja_id UUID,
    p_metodo_pago VARCHAR DEFAULT 'efectivo',
    p_monto_recibido NUMERIC DEFAULT NULL,
    p_descuento NUMERIC DEFAULT 0.00,
    p_referencia_comprobante VARCHAR DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_sesion RECORD;
    v_caja RECORD;
    v_venta_id UUID;
    v_consumo RECORD;
    v_monto_total NUMERIC(10,2);
    v_cambio NUMERIC(10,2) := 0.00;

    -- Variables para pago mixto
    v_ref_json JSONB;
    v_monto_efectivo NUMERIC(10,2) := 0.00;
    v_monto_qr NUMERIC(10,2) := 0.00;
    v_monto_recibido_efectivo NUMERIC(10,2) := 0.00;
    v_ref_texto VARCHAR := NULL;
BEGIN
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND OR v_sesion.estado <> 'finalizada' THEN
        RAISE EXCEPTION 'La sesión no existe o no ha sido finalizada para cobro.';
    END IF;

    SELECT * INTO v_caja FROM public.cajas WHERE id = p_caja_id FOR UPDATE;
    IF NOT FOUND OR v_caja.estado <> 'abierta' THEN
        RAISE EXCEPTION 'La caja especificada no está abierta.';
    END IF;

    v_monto_total := GREATEST(0.00, (v_sesion.monto_tiempo + v_sesion.monto_consumos) - COALESCE(p_descuento, 0.00));

    -- 1. Crear registro de venta comercial
    INSERT INTO public.ventas (
        sesion_id,
        caja_id,
        tipo_venta,
        cliente_nombre,
        subtotal_tiempo,
        subtotal_productos,
        descuento,
        total,
        estado,
        usuario_id
    ) VALUES (
        p_sesion_id,
        p_caja_id,
        'sesion_billar',
        v_sesion.cliente_nombre,
        v_sesion.monto_tiempo,
        v_sesion.monto_consumos,
        COALESCE(p_descuento, 0.00),
        v_monto_total,
        'pagada',
        p_usuario_id
    ) RETURNING id INTO v_venta_id;

    -- 2. Detalle del tiempo de billar
    INSERT INTO public.detalles_venta (
        venta_id,
        concepto,
        cantidad,
        precio_unitario,
        subtotal
    ) VALUES (
        v_venta_id,
        'Tiempo de billar (' || v_sesion.minutos_cobrables || ' min)',
        1,
        v_sesion.monto_tiempo,
        v_sesion.monto_tiempo
    );

    -- 3. Detalles de productos consumidos
    FOR v_consumo IN 
        SELECT cm.*, p.nombre as producto_nombre 
        FROM public.consumos_mesa cm
        JOIN public.productos p ON p.id = cm.producto_id
        WHERE cm.sesion_id = p_sesion_id AND cm.estado = 'confirmado'
    LOOP
        INSERT INTO public.detalles_venta (
            venta_id,
            producto_id,
            concepto,
            cantidad,
            precio_unitario,
            subtotal
        ) VALUES (
            v_venta_id,
            v_consumo.producto_id,
            v_consumo.producto_nombre,
            v_consumo.cantidad,
            v_consumo.precio_unitario,
            v_consumo.subtotal
        );
    END LOOP;

    -- 4. Registrar pago y afectar caja
    IF p_metodo_pago = 'mixto' THEN
        IF p_referencia_comprobante IS NOT NULL AND p_referencia_comprobante LIKE '{%}' THEN
            v_ref_json := p_referencia_comprobante::JSONB;
            v_monto_efectivo := COALESCE((v_ref_json->>'monto_efectivo')::NUMERIC, 0.00);
            v_monto_qr := COALESCE((v_ref_json->>'monto_qr')::NUMERIC, 0.00);
            v_monto_recibido_efectivo := COALESCE((v_ref_json->>'efectivo_recibido')::NUMERIC, v_monto_efectivo);
            v_ref_texto := v_ref_json->>'referencia_qr';
        ELSE
            v_monto_efectivo := COALESCE(p_monto_recibido, 0.00);
            v_monto_qr := GREATEST(0.00, v_monto_total - v_monto_efectivo);
            v_monto_recibido_efectivo := v_monto_efectivo;
            v_ref_texto := p_referencia_comprobante;
        END IF;

        IF (v_monto_efectivo + v_monto_qr) <> v_monto_total THEN
            RAISE EXCEPTION 'La suma de efectivo (Bs. %) y QR (Bs. %) debe ser igual al total (Bs. %).', 
                v_monto_efectivo, v_monto_qr, v_monto_total;
        END IF;

        IF v_monto_recibido_efectivo < v_monto_efectivo THEN
            RAISE EXCEPTION 'El efectivo recibido (Bs. %) es menor a la parte en efectivo (Bs. %).', 
                v_monto_recibido_efectivo, v_monto_efectivo;
        END IF;

        v_cambio := v_monto_recibido_efectivo - v_monto_efectivo;

        -- Parte Efectivo
        IF v_monto_efectivo > 0 THEN
            INSERT INTO public.pagos (
                venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
            ) VALUES (
                v_venta_id, p_caja_id, 'efectivo', v_monto_efectivo, v_monto_recibido_efectivo, v_cambio, 'Liquidación Mesa - Parte Efectivo', p_usuario_id
            );

            UPDATE public.cajas 
            SET monto_ventas_efectivo = monto_ventas_efectivo + v_monto_efectivo,
                monto_esperado_efectivo = monto_esperado_efectivo + v_monto_efectivo
            WHERE id = p_caja_id;

            INSERT INTO public.movimientos_caja (
                caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
            ) VALUES (
                p_caja_id, 'ingreso_sesion', v_monto_efectivo, 'efectivo', p_sesion_id, 'Cobro sesión de mesa (Mixto - Efectivo)', p_usuario_id
            );
        END IF;

        -- Parte QR
        IF v_monto_qr > 0 THEN
            INSERT INTO public.pagos (
                venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
            ) VALUES (
                v_venta_id, p_caja_id, 'qr', v_monto_qr, v_monto_qr, 0.00, COALESCE(v_ref_texto, 'Liquidación Mesa - Parte QR'), p_usuario_id
            );

            UPDATE public.cajas 
            SET monto_ventas_qr = monto_ventas_qr + v_monto_qr 
            WHERE id = p_caja_id;

            INSERT INTO public.movimientos_caja (
                caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
            ) VALUES (
                p_caja_id, 'ingreso_sesion', v_monto_qr, 'qr', p_sesion_id, 'Cobro sesión de mesa (Mixto - QR)', p_usuario_id
            );
        END IF;

    ELSIF p_metodo_pago = 'efectivo' THEN
        IF p_monto_recibido IS NOT NULL AND p_monto_recibido < v_monto_total THEN
            RAISE EXCEPTION 'El monto recibido (Bs. %) es insuficiente para el total (Bs. %).', p_monto_recibido, v_monto_total;
        END IF;
        
        IF p_monto_recibido IS NOT NULL THEN
            v_cambio := p_monto_recibido - v_monto_total;
        ELSE
            p_monto_recibido := v_monto_total;
        END IF;

        INSERT INTO public.pagos (
            venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
        ) VALUES (
            v_venta_id, p_caja_id, 'efectivo', v_monto_total, p_monto_recibido, v_cambio, p_referencia_comprobante, p_usuario_id
        );

        UPDATE public.cajas 
        SET monto_ventas_efectivo = monto_ventas_efectivo + v_monto_total,
            monto_esperado_efectivo = monto_esperado_efectivo + v_monto_total
        WHERE id = p_caja_id;

        INSERT INTO public.movimientos_caja (
            caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
        ) VALUES (
            p_caja_id, 'ingreso_sesion', v_monto_total, 'efectivo', p_sesion_id, 'Cobro sesión de mesa', p_usuario_id
        );

    ELSIF p_metodo_pago = 'qr' THEN
        p_monto_recibido := v_monto_total;

        INSERT INTO public.pagos (
            venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
        ) VALUES (
            v_venta_id, p_caja_id, 'qr', v_monto_total, p_monto_recibido, 0.00, p_referencia_comprobante, p_usuario_id
        );

        UPDATE public.cajas 
        SET monto_ventas_qr = monto_ventas_qr + v_monto_total 
        WHERE id = p_caja_id;

        INSERT INTO public.movimientos_caja (
            caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
        ) VALUES (
            p_caja_id, 'ingreso_sesion', v_monto_total, 'qr', p_sesion_id, 'Cobro sesión de mesa (QR)', p_usuario_id
        );

    ELSE -- tarjeta u otro
        p_monto_recibido := v_monto_total;

        INSERT INTO public.pagos (
            venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
        ) VALUES (
            v_venta_id, p_caja_id, p_metodo_pago, v_monto_total, p_monto_recibido, 0.00, p_referencia_comprobante, p_usuario_id
        );

        UPDATE public.cajas 
        SET monto_ventas_tarjeta = monto_ventas_tarjeta + v_monto_total 
        WHERE id = p_caja_id;

        INSERT INTO public.movimientos_caja (
            caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
        ) VALUES (
            p_caja_id, 'ingreso_sesion', v_monto_total, p_metodo_pago, p_sesion_id, 'Cobro sesión de mesa (' || p_metodo_pago || ')', p_usuario_id
        );
    END IF;

    -- 5. Marcar sesión como pagada
    UPDATE public.sesiones_billar 
    SET estado = 'pagada',
        monto_total = v_monto_total
    WHERE id = p_sesion_id;

    -- 6. Liberar la mesa físicamente
    UPDATE public.mesas 
    SET estado = 'disponible',
        sesion_actual_id = NULL
    WHERE id = v_sesion.mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'venta_id', v_venta_id,
        'total', v_monto_total,
        'cambio', v_cambio,
        'mensaje', 'Sesión liquidada y mesa liberada correctamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 10. FUNCION: VENTA DIRECTA EN MOSTRADOR (SIN MESA)
DROP FUNCTION IF EXISTS public.venta_directa_pos(UUID, VARCHAR, JSONB, VARCHAR, NUMERIC, NUMERIC, VARCHAR, UUID);

CREATE OR REPLACE FUNCTION public.venta_directa_pos(
    p_caja_id UUID,
    p_cliente_nombre VARCHAR,
    p_items JSONB, -- Formato: [{"producto_id": "uuid", "cantidad": 2}, ...]
    p_metodo_pago VARCHAR DEFAULT 'efectivo',
    p_monto_recibido NUMERIC DEFAULT NULL,
    p_descuento NUMERIC DEFAULT 0.00,
    p_referencia_comprobante VARCHAR DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_caja RECORD;
    v_venta_id UUID;
    v_item JSONB;
    v_producto RECORD;
    v_total_productos NUMERIC(10,2) := 0.00;
    v_total_venta NUMERIC(10,2);
    v_subtotal_item NUMERIC(10,2);
    v_cantidad INT;
    v_producto_id UUID;
    v_cambio NUMERIC(10,2) := 0.00;
    v_nuevo_stock INT;

    -- Variables para pago mixto
    v_ref_json JSONB;
    v_monto_efectivo NUMERIC(10,2) := 0.00;
    v_monto_qr NUMERIC(10,2) := 0.00;
    v_monto_recibido_efectivo NUMERIC(10,2) := 0.00;
    v_ref_texto VARCHAR := NULL;
BEGIN
    SELECT * INTO v_caja FROM public.cajas WHERE id = p_caja_id FOR UPDATE;
    IF NOT FOUND OR v_caja.estado <> 'abierta' THEN
        RAISE EXCEPTION 'La caja no existe o está cerrada.';
    END IF;

    -- Si p_items llega como texto/string escapado (ej. desde algunos clientes HTTP)
    IF jsonb_typeof(p_items) = 'string' THEN
        p_items := (p_items #>> '{}')::jsonb;
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'No se enviaron productos para la venta.';
    END IF;

    -- Crear venta inicial para obtener el ID
    INSERT INTO public.ventas (
        caja_id,
        tipo_venta,
        cliente_nombre,
        subtotal_tiempo,
        subtotal_productos,
        descuento,
        total,
        estado,
        usuario_id
    ) VALUES (
        p_caja_id,
        'venta_directa',
        COALESCE(p_cliente_nombre, 'Venta Mostrador'),
        0.00,
        0.00,
        COALESCE(p_descuento, 0.00),
        0.00,
        'pagada',
        p_usuario_id
    ) RETURNING id INTO v_venta_id;

    -- Iterar productos, validar stock y descontar
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad <= 0 THEN
            RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
        END IF;

        SELECT * INTO v_producto FROM public.productos WHERE id = v_producto_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto con ID % no encontrado.', v_producto_id;
        END IF;

        IF v_producto.stock < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para %. Disponible: %, Solicitado: %', 
                v_producto.nombre, v_producto.stock, v_cantidad;
        END IF;

        v_subtotal_item := ROUND(v_cantidad * v_producto.precio_venta, 2);
        v_total_productos := v_total_productos + v_subtotal_item;
        v_nuevo_stock := v_producto.stock - v_cantidad;

        -- Descontar stock
        UPDATE public.productos SET stock = v_nuevo_stock WHERE id = v_producto_id;

        -- Registrar KARDEX
        INSERT INTO public.movimientos_inventario (
            producto_id,
            tipo,
            cantidad,
            stock_anterior,
            stock_nuevo,
            referencia_id,
            motivo,
            usuario_id
        ) VALUES (
            v_producto_id,
            'venta_directa',
            -v_cantidad,
            v_producto.stock,
            v_nuevo_stock,
            v_venta_id,
            'Venta directa en mostrador',
            p_usuario_id
        );

        -- Registrar detalle de venta
        INSERT INTO public.detalles_venta (
            venta_id,
            producto_id,
            concepto,
            cantidad,
            precio_unitario,
            subtotal
        ) VALUES (
            v_venta_id,
            v_producto_id,
            v_producto.nombre,
            v_cantidad,
            v_producto.precio_venta,
            v_subtotal_item
        );
    END LOOP;

    -- Calcular total final
    v_total_venta := GREATEST(0.00, v_total_productos - COALESCE(p_descuento, 0.00));

    -- Actualizar venta con los totales reales
    UPDATE public.ventas 
    SET subtotal_productos = v_total_productos,
        total = v_total_venta
    WHERE id = v_venta_id;

    -- GESTIÓN DE PAGOS SEGÚN MÉTODO
    IF p_metodo_pago = 'mixto' THEN
        -- Extraer desglose de efectivo y QR
        IF p_referencia_comprobante IS NOT NULL AND p_referencia_comprobante LIKE '{%}' THEN
            v_ref_json := p_referencia_comprobante::JSONB;
            v_monto_efectivo := COALESCE((v_ref_json->>'monto_efectivo')::NUMERIC, 0.00);
            v_monto_qr := COALESCE((v_ref_json->>'monto_qr')::NUMERIC, 0.00);
            v_monto_recibido_efectivo := COALESCE((v_ref_json->>'efectivo_recibido')::NUMERIC, v_monto_efectivo);
            v_ref_texto := v_ref_json->>'referencia_qr';
        ELSE
            v_monto_efectivo := COALESCE(p_monto_recibido, 0.00);
            v_monto_qr := GREATEST(0.00, v_total_venta - v_monto_efectivo);
            v_monto_recibido_efectivo := v_monto_efectivo;
            v_ref_texto := p_referencia_comprobante;
        END IF;

        IF (v_monto_efectivo + v_monto_qr) <> v_total_venta THEN
            RAISE EXCEPTION 'La suma de efectivo (Bs. %) y QR (Bs. %) debe ser igual al total (Bs. %).', 
                v_monto_efectivo, v_monto_qr, v_total_venta;
        END IF;

        IF v_monto_recibido_efectivo < v_monto_efectivo THEN
            RAISE EXCEPTION 'El efectivo recibido (Bs. %) es menor al monto en efectivo requerido (Bs. %).', 
                v_monto_recibido_efectivo, v_monto_efectivo;
        END IF;

        v_cambio := v_monto_recibido_efectivo - v_monto_efectivo;

        -- 1. Pago parte Efectivo
        IF v_monto_efectivo > 0 THEN
            INSERT INTO public.pagos (
                venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
            ) VALUES (
                v_venta_id, p_caja_id, 'efectivo', v_monto_efectivo, v_monto_recibido_efectivo, v_cambio, 'Pago Mixto (Efectivo)', p_usuario_id
            );

            UPDATE public.cajas 
            SET monto_ventas_efectivo = monto_ventas_efectivo + v_monto_efectivo,
                monto_esperado_efectivo = monto_esperado_efectivo + v_monto_efectivo
            WHERE id = p_caja_id;

            INSERT INTO public.movimientos_caja (
                caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
            ) VALUES (
                p_caja_id, 'ingreso_venta_directa', v_monto_efectivo, 'efectivo', v_venta_id, 'Venta directa en mostrador (Parte Efectivo)', p_usuario_id
            );
        END IF;

        -- 2. Pago parte QR
        IF v_monto_qr > 0 THEN
            INSERT INTO public.pagos (
                venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
            ) VALUES (
                v_venta_id, p_caja_id, 'qr', v_monto_qr, v_monto_qr, 0.00, COALESCE(v_ref_texto, 'Pago Mixto (QR)'), p_usuario_id
            );

            UPDATE public.cajas 
            SET monto_ventas_qr = monto_ventas_qr + v_monto_qr 
            WHERE id = p_caja_id;

            INSERT INTO public.movimientos_caja (
                caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
            ) VALUES (
                p_caja_id, 'ingreso_venta_directa', v_monto_qr, 'qr', v_venta_id, 'Venta directa en mostrador (Parte QR)', p_usuario_id
            );
        END IF;

    ELSIF p_metodo_pago = 'efectivo' THEN
        IF p_monto_recibido IS NOT NULL AND p_monto_recibido < v_total_venta THEN
            RAISE EXCEPTION 'El monto recibido (Bs. %) es insuficiente para el total (Bs. %).', p_monto_recibido, v_total_venta;
        END IF;

        IF p_monto_recibido IS NOT NULL THEN
            v_cambio := p_monto_recibido - v_total_venta;
        ELSE
            p_monto_recibido := v_total_venta;
        END IF;

        INSERT INTO public.pagos (
            venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
        ) VALUES (
            v_venta_id, p_caja_id, 'efectivo', v_total_venta, p_monto_recibido, v_cambio, p_referencia_comprobante, p_usuario_id
        );

        UPDATE public.cajas 
        SET monto_ventas_efectivo = monto_ventas_efectivo + v_total_venta,
            monto_esperado_efectivo = monto_esperado_efectivo + v_total_venta
        WHERE id = p_caja_id;

        INSERT INTO public.movimientos_caja (
            caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
        ) VALUES (
            p_caja_id, 'ingreso_venta_directa', v_total_venta, 'efectivo', v_venta_id, 'Venta directa en mostrador', p_usuario_id
        );

    ELSIF p_metodo_pago = 'qr' THEN
        p_monto_recibido := v_total_venta;

        INSERT INTO public.pagos (
            venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
        ) VALUES (
            v_venta_id, p_caja_id, 'qr', v_total_venta, p_monto_recibido, 0.00, p_referencia_comprobante, p_usuario_id
        );

        UPDATE public.cajas 
        SET monto_ventas_qr = monto_ventas_qr + v_total_venta 
        WHERE id = p_caja_id;

        INSERT INTO public.movimientos_caja (
            caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
        ) VALUES (
            p_caja_id, 'ingreso_venta_directa', v_total_venta, 'qr', v_venta_id, 'Venta directa en mostrador (QR)', p_usuario_id
        );

    ELSE -- tarjeta u otro
        p_monto_recibido := v_total_venta;

        INSERT INTO public.pagos (
            venta_id, caja_id, metodo_pago, monto, monto_recibido, cambio, referencia_comprobante, usuario_id
        ) VALUES (
            v_venta_id, p_caja_id, p_metodo_pago, v_total_venta, p_monto_recibido, 0.00, p_referencia_comprobante, p_usuario_id
        );

        UPDATE public.cajas 
        SET monto_ventas_tarjeta = monto_ventas_tarjeta + v_total_venta 
        WHERE id = p_caja_id;

        INSERT INTO public.movimientos_caja (
            caja_id, tipo, monto, metodo_pago, referencia_id, descripcion, usuario_id
        ) VALUES (
            p_caja_id, 'ingreso_venta_directa', v_total_venta, p_metodo_pago, v_venta_id, 'Venta directa en mostrador (' || p_metodo_pago || ')', p_usuario_id
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'venta_id', v_venta_id,
        'total', v_total_venta,
        'monto_recibido', COALESCE(v_monto_recibido_efectivo, p_monto_recibido),
        'cambio', v_cambio,
        'mensaje', 'Venta directa procesada con éxito.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 11. FUNCION: APERTURA DE CAJA
CREATE OR REPLACE FUNCTION public.abrir_caja(
    p_nombre VARCHAR DEFAULT 'Caja Principal',
    p_monto_inicial NUMERIC DEFAULT 0.00,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_caja_abierta RECORD;
    v_caja_id UUID;
BEGIN
    IF p_monto_inicial < 0 THEN
        RAISE EXCEPTION 'El monto inicial no puede ser negativo.';
    END IF;

    -- Verificar que no haya una caja abierta actualmente
    SELECT * INTO v_caja_abierta FROM public.cajas WHERE estado = 'abierta' LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Ya existe una caja abierta (ID: %, Abierta por: %). Debe cerrarse antes de abrir una nueva.', 
            v_caja_abierta.id, v_caja_abierta.hora_apertura;
    END IF;

    INSERT INTO public.cajas (
        nombre,
        usuario_apertura_id,
        monto_inicial,
        monto_esperado_efectivo,
        estado,
        hora_apertura
    ) VALUES (
        COALESCE(p_nombre, 'Caja Principal'),
        p_usuario_id,
        COALESCE(p_monto_inicial, 0.00),
        COALESCE(p_monto_inicial, 0.00),
        'abierta',
        NOW()
    ) RETURNING id INTO v_caja_id;

    RETURN jsonb_build_object(
        'success', true,
        'caja_id', v_caja_id,
        'monto_inicial', p_monto_inicial,
        'mensaje', 'Caja abierta exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 12. FUNCION: CIERRE DE CAJA Y ARQUEO
CREATE OR REPLACE FUNCTION public.cerrar_caja(
    p_caja_id UUID,
    p_monto_real_efectivo NUMERIC,
    p_observaciones TEXT DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_caja RECORD;
    v_esperado NUMERIC(10,2);
    v_diferencia NUMERIC(10,2);
BEGIN
    SELECT * INTO v_caja FROM public.cajas WHERE id = p_caja_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La caja no existe.';
    END IF;

    IF v_caja.estado = 'cerrada' THEN
        RAISE EXCEPTION 'Esta caja ya se encuentra cerrada.';
    END IF;

    v_esperado := v_caja.monto_inicial + v_caja.monto_ventas_efectivo + v_caja.monto_ingresos_extra - v_caja.monto_egresos;
    v_diferencia := p_monto_real_efectivo - v_esperado;

    UPDATE public.cajas 
    SET estado = 'cerrada',
        usuario_cierre_id = p_usuario_id,
        hora_cierre = NOW(),
        monto_esperado_efectivo = v_esperado,
        monto_real_efectivo = p_monto_real_efectivo,
        diferencia = v_diferencia,
        observaciones = p_observaciones
    WHERE id = p_caja_id;

    RETURN jsonb_build_object(
        'success', true,
        'caja_id', p_caja_id,
        'monto_esperado', v_esperado,
        'monto_real', p_monto_real_efectivo,
        'diferencia', v_diferencia,
        'mensaje', 'Caja cerrada y arqueada exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
