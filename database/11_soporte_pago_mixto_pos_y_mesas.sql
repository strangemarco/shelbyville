-- =========================================================================
-- SHELBYVILLE BILLIARD CLUB - SOPORTE DE PAGO MIXTO (EFECTIVO + QR)
-- Permite dividir pagos en parte Efectivo y parte QR en:
-- 1. Venta Directa en POS (Mostrador)
-- 2. Liquidación de Cuentas / Mesas de Billar
-- =========================================================================

-- 1. ACTUALIZAR FUNCION: venta_directa_pos
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


-- 2. ACTUALIZAR FUNCION: liquidar_sesion_mesa
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
