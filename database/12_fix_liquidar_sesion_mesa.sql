-- =========================================================================
-- CORRECCIÓN: liquidar_sesion_mesa
-- Permite liquidar directamente sesiones en curso ('activa', 'pausada', 'pendiente_pago'),
-- congela el tiempo, liquida la cuenta y libera la mesa físicamente.
-- =========================================================================

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
    v_calculo JSONB;

    -- Variables para pago mixto
    v_ref_json JSONB;
    v_monto_efectivo NUMERIC(10,2) := 0.00;
    v_monto_qr NUMERIC(10,2) := 0.00;
    v_monto_recibido_efectivo NUMERIC(10,2) := 0.00;
    v_ref_texto VARCHAR := NULL;
BEGIN
    -- 1. Validar existencia de sesión
    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    -- 2. Validar que la sesión esté en curso o pendiente de cobro
    IF v_sesion.estado NOT IN ('activa', 'pausada', 'pendiente_pago') THEN
        RAISE EXCEPTION 'La sesión ya no está disponible para cobro (Estado actual: %).', v_sesion.estado;
    END IF;

    -- 3. Validar caja abierta
    SELECT * INTO v_caja FROM public.cajas WHERE id = p_caja_id FOR UPDATE;
    IF NOT FOUND OR v_caja.estado <> 'abierta' THEN
        RAISE EXCEPTION 'La caja especificada no está abierta.';
    END IF;

    -- 4. Si la sesión estaba en juego o pausada, cerrar pausas y calcular tiempo/monto final
    IF v_sesion.estado = 'pausada' THEN
        UPDATE public.pausas_sesion 
        SET hora_fin = NOW(),
            duracion_segundos = EXTRACT(EPOCH FROM (NOW() - hora_inicio))::INT
        WHERE sesion_id = p_sesion_id AND hora_fin IS NULL;
    END IF;

    IF v_sesion.estado IN ('activa', 'pausada') THEN
        UPDATE public.sesiones_billar
        SET hora_fin = NOW(),
            usuario_cierre_id = p_usuario_id
        WHERE id = p_sesion_id;

        -- Calcular montos congelados
        v_calculo := public.calcular_tiempo_y_monto_sesion(p_sesion_id);

        UPDATE public.sesiones_billar
        SET minutos_cobrables = (v_calculo->>'minutos_cobrables')::INT,
            monto_tiempo = (v_calculo->>'monto_tiempo')::NUMERIC,
            monto_total = (v_calculo->>'monto_total')::NUMERIC
        WHERE id = p_sesion_id;

        -- Refrescar registro en memoria
        SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id;
    END IF;

    v_monto_total := GREATEST(0.00, (v_sesion.monto_tiempo + v_sesion.monto_consumos) - COALESCE(p_descuento, 0.00));

    -- 5. Crear registro de venta comercial
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

    -- 6. Detalle del tiempo de billar
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

    -- 7. Detalles de productos consumidos
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

    -- 8. Registrar pagos y movimientos contables
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

    -- 9. Marcar sesión como finalizada
    UPDATE public.sesiones_billar 
    SET estado = 'finalizada',
        monto_descuento = COALESCE(p_descuento, 0.00),
        monto_total = v_monto_total,
        actualizado_en = NOW()
    WHERE id = p_sesion_id;

    -- 10. Liberar la mesa físicamente
    UPDATE public.mesas 
    SET estado = 'disponible',
        actualizado_en = NOW()
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
