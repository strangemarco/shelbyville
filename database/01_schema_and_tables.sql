-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 01: Extensiones, Tipos y Creación de Tablas
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. EXTENSIONES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. TABLA DE ROLES
CREATE TABLE IF NOT EXISTS public.roles (
    id VARCHAR(30) PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    descripcion TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TABLA DE PERFILES (Vinculada a auth.users de Supabase)
CREATE TABLE IF NOT EXISTS public.perfiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    rol_id VARCHAR(30) NOT NULL REFERENCES public.roles(id) DEFAULT 'cajero',
    nombre_completo VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    activo BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. TABLA DE TARIFAS DE BILLAR
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

-- 5. TABLA DE MESAS
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

-- 6. TABLA DE SESIONES DE BILLAR
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

-- 7. TABLA DE PAUSAS EN SESIONES DE BILLAR
CREATE TABLE IF NOT EXISTS public.pausas_sesion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sesion_id UUID NOT NULL REFERENCES public.sesiones_billar(id) ON DELETE CASCADE,
    hora_inicio TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hora_fin TIMESTAMPTZ,
    duracion_segundos INT,
    motivo VARCHAR(255),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. TABLA DE CATEGORIAS DE PRODUCTOS
CREATE TABLE IF NOT EXISTS public.categorias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    icono VARCHAR(50) DEFAULT 'Layers',
    orden INT DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. TABLA DE PRODUCTOS
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

-- 10. TABLA DE MOVIMIENTOS DE INVENTARIO (KARDEX)
CREATE TABLE IF NOT EXISTS public.movimientos_inventario (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id UUID NOT NULL REFERENCES public.productos(id) ON DELETE RESTRICT,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('entrada', 'consumo_mesa', 'venta_directa', 'ajuste_positivo', 'ajuste_negativo', 'anulacion')),
    cantidad INT NOT NULL,
    stock_anterior INT NOT NULL,
    stock_nuevo INT NOT NULL,
    referencia_id UUID, -- sesion_id o venta_id
    motivo TEXT,
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 11. TABLA DE CONSUMOS ASOCIADOS A MESA
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

-- 12. TABLA DE CAJAS (TURNOS / APERTURAS Y CIERRES)
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

-- 13. TABLA DE MOVIMIENTOS DE CAJA (INGRESOS Y EGRESOS DIRECTOS)
CREATE TABLE IF NOT EXISTS public.movimientos_caja (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caja_id UUID NOT NULL REFERENCES public.cajas(id) ON DELETE CASCADE,
    tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('ingreso_sesion', 'ingreso_venta_directa', 'ingreso_manual', 'egreso_gasto', 'egreso_retiro')),
    monto NUMERIC(10,2) NOT NULL CHECK (monto > 0),
    metodo_pago VARCHAR(30) NOT NULL DEFAULT 'efectivo' CHECK (metodo_pago IN ('efectivo', 'qr', 'tarjeta', 'transferencia')),
    referencia_id UUID, -- sesion_id o venta_id
    descripcion TEXT NOT NULL,
    usuario_id UUID REFERENCES auth.users(id),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 14. TABLA DE VENTAS (COMPROBANTES / REGISTRO COMERCIAL)
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

-- 15. TABLA DE DETALLES DE VENTA
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

-- 16. TABLA DE PAGOS
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

-- 17. TABLA DE AUDITORIA
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

-- 18. INDICES PARA RENDIMIENTO
CREATE INDEX IF NOT EXISTS idx_sesiones_mesa_estado ON public.sesiones_billar(mesa_id, estado);
CREATE INDEX IF NOT EXISTS idx_sesiones_estado ON public.sesiones_billar(estado);
CREATE INDEX IF NOT EXISTS idx_consumos_sesion ON public.consumos_mesa(sesion_id);
CREATE INDEX IF NOT EXISTS idx_mov_inventario_prod ON public.movimientos_inventario(producto_id);
CREATE INDEX IF NOT EXISTS idx_ventas_caja ON public.ventas(caja_id);
CREATE INDEX IF NOT EXISTS idx_pagos_venta ON public.pagos(venta_id);
CREATE INDEX IF NOT EXISTS idx_cajas_estado ON public.cajas(estado);
CREATE INDEX IF NOT EXISTS idx_mov_caja_caja ON public.movimientos_caja(caja_id);
