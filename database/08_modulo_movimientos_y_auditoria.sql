-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 08: Módulo Integral de Movimientos, Bitácora y Auditoría del Sistema
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. ASEGURAR PERMISOS RLS EN TABLA DE AUDITORIA
ALTER TABLE public.auditoria ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lectura de auditoria para administradores" ON public.auditoria;
DROP POLICY IF EXISTS "Acceso total a auditoria" ON public.auditoria;

CREATE POLICY "Acceso total a auditoria"
    ON public.auditoria FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 2. FUNCION GENERICA DE AUDITORIA AUTOMÁTICA
CREATE OR REPLACE FUNCTION public.fn_registrar_auditoria()
RETURNS TRIGGER AS $$
DECLARE
    v_registro_id UUID;
    v_usuario_id UUID := auth.uid();
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_registro_id := OLD.id;
        INSERT INTO public.auditoria (tabla, operacion, registro_id, datos_anteriores, usuario_id)
        VALUES (TG_TABLE_NAME, TG_OP, v_registro_id, to_jsonb(OLD), v_usuario_id);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        v_registro_id := NEW.id;
        INSERT INTO public.auditoria (tabla, operacion, registro_id, datos_anteriores, datos_nuevos, usuario_id)
        VALUES (TG_TABLE_NAME, TG_OP, v_registro_id, to_jsonb(OLD), to_jsonb(NEW), v_usuario_id);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        v_registro_id := NEW.id;
        INSERT INTO public.auditoria (tabla, operacion, registro_id, datos_nuevos, usuario_id)
        VALUES (TG_TABLE_NAME, TG_OP, v_registro_id, to_jsonb(NEW), v_usuario_id);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. TRIGGERS DE AUDITORIA EN TABLAS PRINCIPALES
DROP TRIGGER IF EXISTS trg_audit_sesiones ON public.sesiones_billar;
CREATE TRIGGER trg_audit_sesiones
    AFTER INSERT OR UPDATE ON public.sesiones_billar
    FOR EACH ROW EXECUTE FUNCTION public.fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_audit_ventas ON public.ventas;
CREATE TRIGGER trg_audit_ventas
    AFTER INSERT OR UPDATE ON public.ventas
    FOR EACH ROW EXECUTE FUNCTION public.fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_audit_mov_caja ON public.movimientos_caja;
CREATE TRIGGER trg_audit_mov_caja
    AFTER INSERT ON public.movimientos_caja
    FOR EACH ROW EXECUTE FUNCTION public.fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_audit_mov_inv ON public.movimientos_inventario;
CREATE TRIGGER trg_audit_mov_inv
    AFTER INSERT ON public.movimientos_inventario
    FOR EACH ROW EXECUTE FUNCTION public.fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_audit_consumos ON public.consumos_mesa;
CREATE TRIGGER trg_audit_consumos
    AFTER INSERT OR UPDATE ON public.consumos_mesa
    FOR EACH ROW EXECUTE FUNCTION public.fn_registrar_auditoria();


-- 4. VISTA UNIFICADA DE MOVIMIENTOS DEL SISTEMA (SECURITY INVOKER ACTIVADO)
CREATE OR REPLACE VIEW public.vista_movimientos_sistema 
WITH (security_invoker = true) AS
-- A. Ventas (Liquidación de Mesas y Ventas Directas)
SELECT 
    v.id AS id,
    'Ventas' AS modulo,
    v.tipo_venta AS tipo,
    CASE 
        WHEN v.tipo_venta = 'mesa' THEN 'Cobro y Liquidación de Mesa'
        ELSE 'Venta Directa de Barra'
    END AS titulo,
    'Ticket: ' || COALESCE(v.cliente_nombre, 'Cliente Mostrador') || ' | Descuento: $' || v.descuento || ' | Total: $' || v.total AS detalle,
    v.total AS monto,
    v.estado AS estado,
    v.usuario_id::TEXT AS usuario,
    v.creado_en AS fecha
FROM public.ventas v

UNION ALL

-- B. Sesiones de Billar (Mesas)
SELECT 
    s.id AS id,
    'Mesas' AS modulo,
    s.estado AS tipo,
    'Mesa ' || COALESCE(m.numero::TEXT, '?') || ' - ' || 
    CASE s.estado
        WHEN 'activa' THEN 'Juego en Curso'
        WHEN 'pausada' THEN 'Sesión Pausada'
        WHEN 'pendiente_pago' THEN 'Tiempo Finalizado (Por Cobrar)'
        WHEN 'finalizada' THEN 'Mesa Cobrada y Liberada'
        WHEN 'anulada' THEN 'Sesión Cancelada'
        ELSE s.estado
    END AS titulo,
    'Cliente: ' || COALESCE(s.cliente_nombre, 'Mostrador') || ' | Tarifa: $' || COALESCE(t.precio_por_hora::TEXT, '0') || '/hr | Minutos: ' || s.minutos_cobrables || ' min' AS detalle,
    s.monto_total AS monto,
    s.estado AS estado,
    s.usuario_inicio_id::TEXT AS usuario,
    COALESCE(s.hora_fin, s.hora_inicio) AS fecha
FROM public.sesiones_billar s
LEFT JOIN public.mesas m ON s.mesa_id = m.id
LEFT JOIN public.tarifas t ON s.tarifa_id = t.id

UNION ALL

-- C. Consumos en Mesas
SELECT 
    c.id AS id,
    'Consumos' AS modulo,
    c.estado AS tipo,
    'Consumo Mesa: ' || COALESCE(p.nombre, 'Producto') AS titulo,
    c.cantidad || 'x ' || COALESCE(p.nombre, 'Producto') || ' a $' || c.precio_unitario || ' c/u' AS detalle,
    c.subtotal AS monto,
    c.estado AS estado,
    c.usuario_id::TEXT AS usuario,
    c.creado_en AS fecha
FROM public.consumos_mesa c
LEFT JOIN public.productos p ON c.producto_id = p.id

UNION ALL

-- D. Movimientos de Caja
SELECT 
    mc.id AS id,
    'Caja' AS modulo,
    mc.tipo AS tipo,
    'Caja: ' || UPPER(mc.tipo) AS titulo,
    mc.descripcion || ' (' || UPPER(mc.metodo_pago) || ')' AS detalle,
    mc.monto AS monto,
    'completado' AS estado,
    mc.usuario_id::TEXT AS usuario,
    mc.creado_en AS fecha
FROM public.movimientos_caja mc

UNION ALL

-- E. Movimientos de Inventario (Kardex)
SELECT 
    mi.id AS id,
    'Inventario' AS modulo,
    mi.tipo AS tipo,
    'Inventario: ' || 
    CASE mi.tipo
        WHEN 'entrada' THEN 'Entrada / Reposición'
        WHEN 'consumo_mesa' THEN 'Salida por Mesa'
        WHEN 'venta_directa' THEN 'Salida por POS'
        WHEN 'ajuste_positivo' THEN 'Ajuste (+)'
        WHEN 'ajuste_negativo' THEN 'Ajuste (-)'
        WHEN 'anulacion' THEN 'Restitución por Anulación'
        ELSE mi.tipo
    END AS titulo,
    COALESCE(p.nombre, 'Producto') || ' | Cantidad: ' || mi.cantidad || ' (Stock: ' || mi.stock_anterior || ' → ' || mi.stock_nuevo || ') - ' || COALESCE(mi.motivo, '') AS detalle,
    NULL::NUMERIC AS monto,
    'registrado' AS estado,
    mi.usuario_id::TEXT AS usuario,
    mi.creado_en AS fecha
FROM public.movimientos_inventario mi
LEFT JOIN public.productos p ON mi.producto_id = p.id;

-- 5. PERMISOS DE LECTURA PARA LA VISTA
GRANT SELECT ON public.vista_movimientos_sistema TO anon, authenticated;
