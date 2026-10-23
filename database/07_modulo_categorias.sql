-- ==============================================================================
-- SHELBYVILLE BILLIARD MANAGEMENT SYSTEM
-- Script 07: Módulo de Gestión de Categorías
-- Base de Datos: PostgreSQL / Supabase
-- ==============================================================================

-- 1. ASEGURAR TABLA DE CATEGORIAS (YA INCLUIDA EN SCHEMA INICIAL)
CREATE TABLE IF NOT EXISTS public.categorias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    icono VARCHAR(50) DEFAULT 'Layers',
    orden INT DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT true,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. POLÍTICAS RLS (ACCESO COMPLETO PARA GESTIÓN EN TERMINAL)
ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lectura de categorias para autenticados" ON public.categorias;
DROP POLICY IF EXISTS "Admins gestionan categorias" ON public.categorias;
DROP POLICY IF EXISTS "Acceso total a categorias" ON public.categorias;

CREATE POLICY "Acceso total a categorias"
    ON public.categorias FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 3. HABILITAR PUBLICACIÓN REALTIME
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'categorias'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.categorias;
    END IF;
END $$;
