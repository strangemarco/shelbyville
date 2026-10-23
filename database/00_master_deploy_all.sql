-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script Master de Despliegue Completo (01 a 05)
-- Base de Datos: PostgreSQL / Supabase
--
-- INSTRUCCIONES:
-- 1. Abre tu Dashboard de Supabase:
--    https://supabase.com/dashboard/project/kdvvuasxusaisqhusnwh/sql/new
-- 2. Copia todo el contenido de este archivo.
-- 3. Pégalo en el SQL Editor y presiona "Run".
-- ==============================================================================

-- PARTE 1: SCHEMA Y TABLAS
-- ==============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.roles (
    id VARCHAR(30) PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    descripcion TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.perfiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    rol_id VARCHAR(30) NOT NULL REFERENCES public.roles(id) DEFAULT 'cajero',
    nombre_completo VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    activo BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tarifas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    precio_por_hora NUMERIC(10,2) NOT NULL CHECK (precio_por_hora >= 0),
    minutos_minimo INT NOT NULL DEFAULT 15 CHECK (minutos_minimo >= 0),
    minutos_tolerancia INT NOT NULL DEFAULT 5 CHECK (minutos_tolerancia >= 0),
    activo BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.mesas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero INT UNIQUE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(50) NOT NULL DEFAULT 'Pool' CHECK (tipo IN ('Pool', 'Carambola', 'Snooker')),
    tarifa_defecto_id UUID REFERENCES public.tarifas(id),
    estado VARCHAR(30) NOT NULL DEFAULT 'disponible' CHECK (estado IN ('disponible', 'ocupada', 'pausada', 'mantenimiento')),
    activa BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sesiones_billar (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mesa_id UUID NOT NULL REFERENCES public.mesas(id),
    tarifa_id UUID NOT NULL REFERENCES public.tarifas(id),
    cliente_nombre VARCHAR(120),
    hora_inicio TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hora_fin TIMESTAMPTZ,
    segundos_pausados INT NOT NULL DEFAULT 0,
    minutos_cobrables INT NOT NULL DEFAULT 0,
    monto_tiempo NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_consumos NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_descuento NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_total NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    estado VARCHAR(30) NOT NULL DEFAULT 'activa' CHECK (estado IN ('activa', 'pausada', 'pendiente_pago', 'finalizada', 'anulada')),
    usuario_inicio_id UUID REFERENCES auth.users(id),
    usuario_cierre_id UUID REFERENCES auth.users(id),
    notas TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pausas_sesion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sesion_id UUID NOT NULL REFERENCES public.sesiones_billar(id) ON DELETE CASCADE,
    hora_inicio TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hora_fin TIMESTAMPTZ,
    duracion_segundos INT,
    motivo VARCHAR(255),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.categorias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    icono VARCHAR(50) DEFAULT 'Layers',
    orden INT DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.productos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    categoria_id UUID REFERENCES public.categorias(id) ON DELETE SET NULL,
    codigo VARCHAR(50) UNIQUE,
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    precio_compra NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (precio_compra >= 0),
    precio_venta NUMERIC(10,2) NOT NULL CHECK (precio_venta >= 0),
    stock INT NOT NULL DEFAULT 0,
    stock_minimo INT NOT NULL DEFAULT 5 CHECK (stock_minimo >= 0),
    activo BOOLEAN NOT NULL DEFAULT true,
    imagen_url TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_stock_non_negative CHECK (stock >= 0)
);

CREATE TABLE IF NOT EXISTS public.movimientos_inventario (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id UUID NOT NULL REFERENCES public.productos(id) ON DELETE RESTRICT,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('entrada', 'consumo_mesa', 'venta_directa', 'ajuste_positivo', 'ajuste_negativo', 'anulacion')),
    cantidad INT NOT NULL,
    stock_anterior INT NOT NULL,
    stock_nuevo INT NOT NULL,
    referencia_id UUID,
    motivo TEXT,
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.consumos_mesa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sesion_id UUID NOT NULL REFERENCES public.sesiones_billar(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES public.productos(id) ON DELETE RESTRICT,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
    estado VARCHAR(30) NOT NULL DEFAULT 'confirmado' CHECK (estado IN ('confirmado', 'anulado')),
    motivo_anulacion TEXT,
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cajas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL DEFAULT 'Caja Principal',
    usuario_apertura_id UUID NOT NULL REFERENCES auth.users(id),
    usuario_cierre_id UUID REFERENCES auth.users(id),
    monto_inicial NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (monto_inicial >= 0),
    monto_ventas_efectivo NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_ventas_qr NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_ventas_tarjeta NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_ingresos_extra NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_egresos NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_esperado_efectivo NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    monto_real_efectivo NUMERIC(10,2),
    diferencia NUMERIC(10,2),
    estado VARCHAR(30) NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta', 'cerrada')),
    hora_apertura TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hora_cierre TIMESTAMPTZ,
    observaciones TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.movimientos_caja (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caja_id UUID NOT NULL REFERENCES public.cajas(id) ON DELETE CASCADE,
    tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('ingreso_sesion', 'ingreso_venta_directa', 'ingreso_manual', 'egreso_gasto', 'egreso_retiro')),
    monto NUMERIC(10,2) NOT NULL CHECK (monto > 0),
    metodo_pago VARCHAR(30) NOT NULL DEFAULT 'efectivo' CHECK (metodo_pago IN ('efectivo', 'qr', 'tarjeta', 'transferencia')),
    referencia_id UUID,
    descripcion TEXT NOT NULL,
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ventas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sesion_id UUID REFERENCES public.sesiones_billar(id),
    caja_id UUID NOT NULL REFERENCES public.cajas(id),
    tipo_venta VARCHAR(30) NOT NULL DEFAULT 'sesion_billar' CHECK (tipo_venta IN ('sesion_billar', 'venta_directa')),
    cliente_nombre VARCHAR(120),
    subtotal_tiempo NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    subtotal_productos NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    descuento NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    total NUMERIC(10,2) NOT NULL CHECK (total >= 0),
    estado VARCHAR(30) NOT NULL DEFAULT 'pagada' CHECK (estado IN ('pagada', 'anulada')),
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.detalles_venta (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id UUID NOT NULL REFERENCES public.ventas(id) ON DELETE CASCADE,
    producto_id UUID REFERENCES public.productos(id) ON DELETE SET NULL,
    concepto VARCHAR(200) NOT NULL,
    cantidad INT NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pagos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id UUID NOT NULL REFERENCES public.ventas(id) ON DELETE CASCADE,
    caja_id UUID NOT NULL REFERENCES public.cajas(id),
    metodo_pago VARCHAR(30) NOT NULL CHECK (metodo_pago IN ('efectivo', 'qr', 'tarjeta', 'transferencia')),
    monto NUMERIC(10,2) NOT NULL CHECK (monto > 0),
    monto_recibido NUMERIC(10,2),
    cambio NUMERIC(10,2) DEFAULT 0.00,
    referencia_comprobante VARCHAR(100),
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.auditoria (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tabla VARCHAR(50) NOT NULL,
    operacion VARCHAR(20) NOT NULL,
    registro_id UUID,
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indices
CREATE INDEX IF NOT EXISTS idx_sesiones_mesa_estado ON public.sesiones_billar(mesa_id, estado);
CREATE INDEX IF NOT EXISTS idx_sesiones_estado ON public.sesiones_billar(estado);
CREATE INDEX IF NOT EXISTS idx_consumos_sesion ON public.consumos_mesa(sesion_id);
CREATE INDEX IF NOT EXISTS idx_mov_inventario_prod ON public.movimientos_inventario(producto_id);
CREATE INDEX IF NOT EXISTS idx_ventas_caja ON public.ventas(caja_id);
CREATE INDEX IF NOT EXISTS idx_pagos_venta ON public.pagos(venta_id);
CREATE INDEX IF NOT EXISTS idx_cajas_estado ON public.cajas(estado);
CREATE INDEX IF NOT EXISTS idx_mov_caja_caja ON public.movimientos_caja(caja_id);


-- PARTE 2: TRIGGERS Y REALTIME
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.fn_actualizar_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizado_en = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_upd_perfiles ON public.perfiles;
CREATE TRIGGER trg_upd_perfiles BEFORE UPDATE ON public.perfiles FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_tarifas ON public.tarifas;
CREATE TRIGGER trg_upd_tarifas BEFORE UPDATE ON public.tarifas FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_mesas ON public.mesas;
CREATE TRIGGER trg_upd_mesas BEFORE UPDATE ON public.mesas FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_sesiones_billar ON public.sesiones_billar;
CREATE TRIGGER trg_upd_sesiones_billar BEFORE UPDATE ON public.sesiones_billar FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_upd_productos ON public.productos;
CREATE TRIGGER trg_upd_productos BEFORE UPDATE ON public.productos FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_timestamp();

CREATE OR REPLACE FUNCTION public.fn_handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_total_usuarios INT;
    v_rol_asignado VARCHAR(30);
    v_nombre VARCHAR(150);
BEGIN
    SELECT COUNT(*) INTO v_total_usuarios FROM public.perfiles;
    IF v_total_usuarios = 0 THEN
        v_rol_asignado := 'admin';
    ELSE
        v_rol_asignado := 'cajero';
    END IF;

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
CREATE TRIGGER trg_on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.fn_handle_new_user();

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'mesas') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mesas;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sesiones_billar') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.sesiones_billar;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'consumos_mesa') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.consumos_mesa;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'cajas') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.cajas;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'productos') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.productos;
    END IF;
END $$;


-- PARTE 3: FUNCIONES DE NEGOCIO (RPC)
-- ==============================================================================

-- 1. Iniciar Sesión
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

    IF v_mesa.estado <> 'disponible' THEN
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

    UPDATE public.mesas SET estado = 'ocupada' WHERE id = p_mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', v_sesion_id,
        'mesa_id', p_mesa_id,
        'mensaje', 'Sesión iniciada exitosamente.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Pausar Sesión
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

    INSERT INTO public.pausas_sesion (sesion_id, hora_inicio, motivo)
    VALUES (p_sesion_id, NOW(), p_motivo);

    UPDATE public.sesiones_billar SET estado = 'pausada' WHERE id = p_sesion_id;
    UPDATE public.mesas SET estado = 'pausada' WHERE id = v_sesion.mesa_id;

    RETURN jsonb_build_object('success', true, 'sesion_id', p_sesion_id, 'mensaje', 'Sesión pausada exitosamente.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Reanudar Sesión
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

    UPDATE public.sesiones_billar 
    SET estado = 'activa',
        segundos_pausados = segundos_pausados + COALESCE(v_duracion_segundos, 0)
    WHERE id = p_sesion_id;

    UPDATE public.mesas SET estado = 'ocupada' WHERE id = v_sesion.mesa_id;

    RETURN jsonb_build_object(
        'success', true,
        'sesion_id', p_sesion_id,
        'segundos_pausados_agregados', v_duracion_segundos,
        'mensaje', 'Sesión reanudada con éxito.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Cambiar Mesa
CREATE OR REPLACE FUNCTION public.cambiar_mesa_sesion(
    p_sesion_id UUID,
    p_nueva_mesa_id UUID,
    p_motivo TEXT DEFAULT 'Cambio de mesa solicitado'
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

    UPDATE public.mesas SET estado = 'disponible' WHERE id = v_mesa_origen.id;
    UPDATE public.mesas SET estado = v_mesa_origen.estado WHERE id = v_mesa_destino.id;

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

-- 5. Calcular Tiempo y Monto
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

    v_hora_corte := COALESCE(v_sesion.hora_fin, v_ahora);

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

    IF v_minutos_transcurridos <= v_tarifa.minutos_tolerancia THEN
        v_minutos_cobrables := 0;
    ELSIF v_minutos_transcurridos < v_tarifa.minutos_minimo THEN
        v_minutos_cobrables := v_tarifa.minutos_minimo;
    ELSE
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

-- 6. Agregar Consumo
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

    SELECT * INTO v_sesion FROM public.sesiones_billar WHERE id = p_sesion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesión no existe.';
    END IF;

    IF v_sesion.estado NOT IN ('activa', 'pausada') THEN
        RAISE EXCEPTION 'No se pueden agregar consumos a una sesión en estado %.', v_sesion.estado;
    END IF;

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

    v_nuevo_stock := v_producto.stock - p_cantidad;
    UPDATE public.productos SET stock = v_nuevo_stock WHERE id = p_producto_id;

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

    UPDATE public.sesiones_billar
    SET monto_consumos = monto_consumos + v_subtotal
    WHERE id = p_sesion_id;

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

-- 7. Anular Consumo
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

    SELECT * INTO v_producto FROM public.productos WHERE id = v_consumo.producto_id FOR UPDATE;
    v_nuevo_stock := v_producto.stock + v_consumo.cantidad;
    UPDATE public.productos SET stock = v_nuevo_stock WHERE id = v_producto.id;

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

    UPDATE public.consumos_mesa 
    SET estado = 'anulado', motivo_anulacion = p_motivo 
    WHERE id = p_consumo_id;

    UPDATE public.sesiones_billar 
    SET monto_consumos = GREATEST(0, monto_consumos - v_consumo.subtotal) 
    WHERE id = v_consumo.sesion_id;

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

-- 8. Finalizar Tiempo
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

    IF v_sesion.estado = 'pausada' THEN
        UPDATE public.pausas_sesion 
        SET hora_fin = NOW(),
            duracion_segundos = EXTRACT(EPOCH FROM (NOW() - hora_inicio))::INT
        WHERE sesion_id = p_sesion_id AND hora_fin IS NULL;
    END IF;

    UPDATE public.sesiones_billar
    SET hora_fin = NOW(),
        estado = 'pendiente_pago',
        usuario_cierre_id = p_usuario_id
    WHERE id = p_sesion_id;

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

-- 9. Liquidar y Cobrar Sesión
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

-- 10. Venta Directa en Mostrador
DROP FUNCTION IF EXISTS public.venta_directa_pos(UUID, VARCHAR, JSONB, VARCHAR, NUMERIC, NUMERIC, VARCHAR, UUID);

CREATE OR REPLACE FUNCTION public.venta_directa_pos(
    p_caja_id UUID,
    p_cliente_nombre VARCHAR,
    p_items JSONB,
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

    IF jsonb_typeof(p_items) = 'string' THEN
        p_items := (p_items #>> '{}')::jsonb;
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'No se enviaron productos para la venta.';
    END IF;

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

        UPDATE public.productos SET stock = v_nuevo_stock WHERE id = v_producto_id;

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

-- 11. Abrir Caja
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

-- 12. Cerrar Caja
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


-- PARTE 4: POLÍTICAS ROW LEVEL SECURITY (RLS)
-- ==============================================================================
ALTER TABLE public.cajas ALTER COLUMN usuario_apertura_id DROP NOT NULL;

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

-- Políticas de Acceso Completo para Modo Terminal / Cajero
DROP POLICY IF EXISTS "Acceso total a mesas" ON public.mesas;
CREATE POLICY "Acceso total a mesas" ON public.mesas FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a tarifas" ON public.tarifas;
CREATE POLICY "Acceso total a tarifas" ON public.tarifas FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a categorias" ON public.categorias;
CREATE POLICY "Acceso total a categorias" ON public.categorias FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a productos" ON public.productos;
CREATE POLICY "Acceso total a productos" ON public.productos FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a sesiones" ON public.sesiones_billar;
CREATE POLICY "Acceso total a sesiones" ON public.sesiones_billar FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a pausas" ON public.pausas_sesion;
CREATE POLICY "Acceso total a pausas" ON public.pausas_sesion FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a consumos" ON public.consumos_mesa;
CREATE POLICY "Acceso total a consumos" ON public.consumos_mesa FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a cajas" ON public.cajas;
CREATE POLICY "Acceso total a cajas" ON public.cajas FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a movimientos de caja" ON public.movimientos_caja;
CREATE POLICY "Acceso total a movimientos de caja" ON public.movimientos_caja FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a ventas" ON public.ventas;
CREATE POLICY "Acceso total a ventas" ON public.ventas FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a detalles de venta" ON public.detalles_venta;
CREATE POLICY "Acceso total a detalles de venta" ON public.detalles_venta FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a pagos" ON public.pagos;
CREATE POLICY "Acceso total a pagos" ON public.pagos FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a movimientos de inventario" ON public.movimientos_inventario;
CREATE POLICY "Acceso total a movimientos de inventario" ON public.movimientos_inventario FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acceso total a roles" ON public.roles;
CREATE POLICY "Acceso total a roles" ON public.roles FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "Acceso total a perfiles" ON public.perfiles;
CREATE POLICY "Acceso total a perfiles" ON public.perfiles FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;


-- PARTE 5: DATOS SEMILLA (SEED DATA)
-- ==============================================================================
INSERT INTO public.roles (id, nombre, descripcion)
VALUES 
    ('admin', 'Administrador', 'Control total de configuración, usuarios, inventario, caja y reportes.'),
    ('cajero', 'Cajero / Operador', 'Gestión de mesas, toma de consumos, cobro de cuentas y arqueo de caja.')
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion;

INSERT INTO public.tarifas (id, nombre, descripcion, precio_por_hora, minutos_minimo, minutos_tolerancia, activo)
VALUES 
    ('11111111-1111-1111-1111-111111111101', 'Tarifa Estándar (Pool)', 'Tarifa regular por hora para mesas de pool bola 8 y 9.', 25.00, 15, 5, true),
    ('11111111-1111-1111-1111-111111111102', 'Tarifa Promo Tarde', 'Tarifa reducida para horario diurno y promociones.', 18.00, 15, 5, true),
    ('11111111-1111-1111-1111-111111111103', 'Tarifa Noche y Finde', 'Tarifa para viernes, sábados y horarios de alta demanda.', 30.00, 15, 5, true),
    ('11111111-1111-1111-1111-111111111104', 'Tarifa Carambola y Snooker VIP', 'Tarifa para mesas profesionales de 3 bandas y snooker.', 35.00, 20, 5, true)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, precio_por_hora = EXCLUDED.precio_por_hora;

INSERT INTO public.mesas (id, numero, nombre, tipo, tarifa_defecto_id, estado, activa)
VALUES 
    ('22222222-2222-2222-2222-222222222201', 1, 'Mesa 1 - Pool Clásica', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222202', 2, 'Mesa 2 - Pool Clásica', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222203', 3, 'Mesa 3 - Pool Central', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222204', 4, 'Mesa 4 - Pool Central', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222205', 5, 'Mesa 5 - Pool Pro', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222206', 6, 'Mesa 6 - Pool Pro', 'Pool', '11111111-1111-1111-1111-111111111101', 'disponible', true),
    ('22222222-2222-2222-2222-222222222207', 7, 'Mesa 7 - Carambola 3 Bandas', 'Carambola', '11111111-1111-1111-1111-111111111104', 'disponible', true),
    ('22222222-2222-2222-2222-222222222208', 8, 'Mesa 8 - Snooker VIP', 'Snooker', '11111111-1111-1111-1111-111111111104', 'disponible', true)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, tipo = EXCLUDED.tipo;

INSERT INTO public.categorias (id, nombre, descripcion, icono, orden, activo)
VALUES 
    ('33333333-3333-3333-3333-333333333301', 'Cervezas', 'Cervezas nacionales, artesanales e importadas.', 'Beer', 1, true),
    ('33333333-3333-3333-3333-333333333302', 'Bebidas & Gaseosas', 'Gaseosas, aguas y energizantes.', 'CupSoda', 2, true),
    ('33333333-3333-3333-3333-333333333303', 'Snacks & Piqueos', 'Papas fritas, nachos, maní y piqueos rápidos.', 'Utensils', 3, true),
    ('33333333-3333-3333-3333-333333333304', 'Tragos & Licores', 'Vasos y jarras de combinados, fernet, whisky y cocteles.', 'Wine', 4, true),
    ('33333333-3333-3333-3333-333333333305', 'Varios', 'Cigarrillos, encendedores y accesorios.', 'Package', 5, true)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, icono = EXCLUDED.icono;

INSERT INTO public.productos (id, categoria_id, codigo, nombre, descripcion, precio_compra, precio_venta, stock, stock_minimo, activo)
VALUES 
    ('44444444-4444-4444-4444-444444444401', '33333333-3333-3333-3333-333333333301', 'CER-01', 'Cerveza Corona 355ml', 'Botella individual fría', 12.00, 20.00, 48, 12, true),
    ('44444444-4444-4444-4444-444444444402', '33333333-3333-3333-3333-333333333301', 'CER-02', 'Cerveza Heineken 330ml', 'Botella individual fría', 12.00, 20.00, 36, 12, true),
    ('44444444-4444-4444-4444-444444444403', '33333333-3333-3333-3333-333333333301', 'CER-03', 'Cerveza Paceña Huari 330ml', 'Cerveza tradicional', 10.00, 18.00, 60, 15, true),
    ('44444444-4444-4444-4444-444444444404', '33333333-3333-3333-3333-333333333302', 'BEB-01', 'Coca Cola 500ml', 'Botella personal', 5.00, 10.00, 40, 10, true),
    ('44444444-4444-4444-4444-444444444405', '33333333-3333-3333-3333-333333333302', 'BEB-02', 'Sprite 500ml', 'Botella personal', 5.00, 10.00, 25, 8, true),
    ('44444444-4444-4444-4444-444444444406', '33333333-3333-3333-3333-333333333302', 'BEB-03', 'Agua Mineral 500ml', 'Con gas / Sin gas', 4.00, 8.00, 30, 10, true),
    ('44444444-4444-4444-4444-444444444407', '33333333-3333-3333-3333-333333333302', 'BEB-04', 'Red Bull 250ml', 'Lata energizante clásica', 14.00, 25.00, 24, 6, true),
    ('44444444-4444-4444-4444-444444444408', '33333333-3333-3333-3333-333333333303', 'SNK-01', 'Papas Fritas Lays 90g', 'Bolsa mediana clásico corte fino', 6.00, 12.00, 20, 5, true),
    ('44444444-4444-4444-4444-444444444409', '33333333-3333-3333-3333-333333333303', 'SNK-02', 'Nachos con Queso Cheddar', 'Porción para mesa con dip caliente', 10.00, 22.00, 15, 4, true),
    ('44444444-4444-4444-4444-444444444410', '33333333-3333-3333-3333-333333333303', 'SNK-03', 'Maní Tostado Salado 100g', 'Piqueo clásico para billar', 4.00, 8.00, 35, 10, true),
    ('44444444-4444-4444-4444-444444444411', '33333333-3333-3333-3333-333333333304', 'TRG-01', 'Fernet Branca con Coca', 'Vaso largo con hielo', 12.00, 25.00, 80, 20, true),
    ('44444444-4444-4444-4444-444444444412', '33333333-3333-3333-3333-333333333304', 'TRG-02', 'Whisky Red Label (Vaso)', 'Vaso con hielo o agua con gas', 15.00, 30.00, 50, 10, true)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, precio_venta = EXCLUDED.precio_venta, stock = EXCLUDED.stock;
