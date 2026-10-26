# 🎱 Shelbyville Billiard Club - Management System

Sistema integral de gestión, control de tiempos de billar, punto de venta (POS), auditoría, reportes financieros y arqueo de caja desarrollado con tecnologías web modernas de alto rendimiento.

Diseñado específicamente para clubes de billar, bares y salas de entretenimiento que requieren control riguroso de mesas por tiempo, venta de productos en mostrador, arqueos de caja transparentes, opciones de pago flexibles (Efectivo, QR y Pagos Mixtos) y reportes ejecutivos en Excel.

---

## 🚀 Tecnologías Principales

- **Frontend:** [.NET 10 Blazor WebAssembly](https://dotnet.microsoft.com/apps/aspnet/web-apps/blazor) (SPA de alto rendimiento en el navegador)
- **Componentes UI:** [MudBlazor 9](https://mudblazor.com/) (Material Design personalizado con temática Luxury Billiard)
- **Exportación de Documentos:** [DocumentFormat.OpenXml](https://github.com/dotnet/Open-XML-SDK) (Librería oficial de Microsoft para generación de hojas de cálculo Excel `.xlsx` nativas y formateadas)
- **Backend & Base de Datos:** [Supabase](https://supabase.com/)
  - **PostgreSQL 15+** con lógica de negocio encapsulada en funciones PL/pgSQL transaccionales (RPC)
  - **GoTrue Auth:** Autenticación segura de usuarios con control de acceso por sesión
  - **Supabase Realtime:** Sincronización en vivo del estado de mesas, caja y movimientos entre dispositivos
- **Tipografía y Estilo:** Google Fonts (*Outfit* para encabezados e *Inter* para datos numéricos y tablas), tema de lujo verde billar (`#0B1210`, `#164F3B`) y acentos dorados (`#D4AF37`).

---

## ✨ Características y Módulos

### 1. 🔒 Control de Acceso y Protección de Sesión
- **Protección de Inicio:** El sistema valida de forma proactiva si existe una sesión activa y guardada en el navegador (`localStorage`).
- **Bloqueo Preventivo:** Si no hay sesión iniciada, las páginas internas y la barra de navegación nunca se renderizan; el sistema muestra una pantalla de carga y redirige de inmediato a la pantalla de **`/login`**.
- **Sesión Persistente:** Mantiene al usuario conectado entre recargas de página o reaperturas del navegador sin exponer credenciales.
- **Cierre de Sesión Seguro:** Limpieza completa de tokens y redirección forzosa al Login.

### 2. 🎱 Control de Mesas de Billar
- **Monitoreo en Tiempo Real:** Visualización en vivo del estado de cada mesa (*Disponible*, *Ocupada*, *Pausada*, *Reservada*, *Mantenimiento*).
- **Cronómetro de Juego:** Cálculo automático del tiempo transcurrido y tarifas por hora con fracciones exactas y minutos de tolerancia de gracia.
- **Consumos a la Mesa:** Carga directa de bebidas, botanas o productos de barra a la cuenta de la mesa con descuento inmediato de inventario.
- **Liquidación y Cobro:**
  - Resumen detallado de tiempo jugado + consumos de barra.
  - Aplicación de descuentos especiales.
  - Métodos de pago: **Efectivo**, **QR / Transferencia**, **Tarjeta** y **Mixto (Efectivo + QR)**.
  - Cálculo automático de desglose, efectivo entregado y vuelto/cambio.
  - Congelamiento de tiempo, cobro en caja y liberación física de la mesa.

### 3. 🛒 Punto de Venta Mostrador (POS)
- Venta directa ágil para clientes en barra o mostrador sin ocupar mesa.
- Búsqueda predictiva de productos por nombre o código de barras.
- Filtro dinámico por categorías.
- Carrito de compras interactivo con validación de stock en tiempo real.
- **Soporte de Pago Mixto:** Desglose configurable de parte en efectivo y parte en QR con cálculo instantáneo de vuelto.
- Función de derivar pedidos del carrito directamente a una mesa activa.

### 4. 💵 Gestión y Arqueo de Caja
- **Apertura de Caja:** Registro de monto inicial y asignación de cajero.
- **Indicador Dinámico en Cabecera:** Chip verde de caja abierta en la barra superior con actualización en tiempo real que **desaparece automáticamente al cerrar la caja**.
- **Discriminación Contable en Vivo:**
  - Ventas en Efectivo (Mesas + Mostrador).
  - Ventas por QR (Mesas + Mostrador).
  - Ventas con Tarjeta.
  - Pagos mixtos desglosados auditables.
- **Cierre y Arqueo:** Comparativa automática entre monto esperado en gaveta y monto real contado con cálculo de descuadre (*Faltante*, *Sobrante* o *Exacto*).

### 5. 📊 Estadísticas, Reportes y Últimas Ventas
- **Métricas de Facturación:** Total recaudado en el turno actual con distribución porcentual por canal (Efectivo, QR, Tarjeta).
- **Ocupación del Salón:** Porcentaje en tiempo real de mesas en juego.
- **Tabla de Últimas 10 Ventas:**
  - Consulta en tiempo real de las transacciones más recientes.
  - Desglose entre tiempo de mesa, consumo de artículos y descuentos.
  - Método de pago utilizado (Efectivo, QR, Tarjeta o Mixto).
  - **Fila expandible interactiva:** Permite ver el detalle específico de productos cobrados, cantidades, precios unitarios y comprobantes de pago de cada ticket.
- **Exportación Oficial a Excel:** Descarga con un clic de un libro `.xlsx` con hojas separadas para el resumen financiero del turno y el listado de ventas.

### 6. 📦 Inventario, KARDEX y Exportación
- Catálogo de productos con costos de compra, precios de venta y control de existencias.
- Alertas visuales de stock mínimo y productos agotados.
- Entrada rápida de mercadería individual o global.
- Registro automatizado de movimientos de inventario (KARDEX).
- **Exportación a Excel:** Reporte descargable con código, nombre, categoría, costos, precios, márgenes, existencias, alertas y valorización monetaria total.

### 7. 📜 Bitácora de Movimientos y Auditoría
- Trazabilidad y registro cronológico de todas las operaciones del sistema (Mesas, Ventas, Caja e Inventario).
- Filtros rápidos por módulo y buscador instantáneo.
- **Exportación a Excel:** Descarga de la bitácora filtrada con fechas, conceptos, importes y estado.

### 8. 👥 Personal, Roles y Configuración
- Roles administrativos: Administrador, Supervisor, Cajero, Mesero y Bartender.
- Módulo de configuración depurado: Gestión de mesas de billar, tarifas por hora y reservas de salón.

---

## 📂 Estructura del Proyecto

```text
Shelbyville/
├── database/                                  # Scripts SQL para despliegue en Supabase
│   ├── 00_master_deploy_all.sql               # Despliegue completo unificado
│   ├── 01_schema_tables_and_types.sql         # Tablas base, constraints y triggers
│   ├── 02_views_and_helpers.sql               # Vistas optimizadas
│   ├── 03_business_rpc_functions.sql          # Procedimientos almacenados transaccionales (RPC)
│   ├── 04_rls_security_policies.sql           # Políticas de seguridad RLS
│   ├── 05_seed_initial_data.sql               # Datos iniciales (Mesas, Categorías, Tarifas)
│   ├── 09_modulo_gestion_mesas_tarifas_reservas.sql # Módulo de reservas y tarifas
│   ├── 10_modulo_usuarios_y_roles.sql         # Gestión administrativa de usuarios y roles
│   ├── 11_soporte_pago_mixto_pos_y_mesas.sql  # Soporte integral de pagos mixtos (Efectivo + QR)
│   └── 12_fix_liquidar_sesion_mesa.sql        # Corrección de liquidación de sesiones de billar
├── Shelbyville/                               # Aplicación Blazor WebAssembly
│   ├── Components/                            # Modales y componentes reutilizables
│   │   ├── ModalCobroMesa.razor               # Modal de liquidación de mesas con soporte mixto
│   │   ├── ModalAperturaCaja.razor            # Modal de inicio de jornada de caja
│   │   ├── ModalAjusteStock.razor             # Entrada de mercadería al inventario
│   │   ├── ModalProducto.razor                # Modal de creación/edición de productos
│   │   ├── ModalMesa.razor                    # Configuración de mesas
│   │   ├── ModalTarifa.razor                  # Gestión de tarifas por hora
│   │   ├── ModalReserva.razor                 # Registro de reservas
│   │   └── ModalUsuario.razor                 # Gestión de personal y contraseñas
│   ├── Layout/                                # Layouts principales de la app
│   │   ├── MainLayout.razor                   # Layout con protección de autenticación y AppBar reactivo
│   │   ├── NavMenu.razor                      # Barra lateral de módulos con logout seguro
│   │   └── EmptyLayout.razor                  # Layout limpio para Login
│   ├── Models/                                # Modelos de datos y mapeos C#
│   ├── Pages/                                 # Vistas principales del sistema
│   │   ├── Home.razor                         # Dashboard principal
│   │   ├── Mesas.razor                        # Tablero de control de mesas de billar
│   │   ├── Pos.razor                          # Punto de venta mostrador
│   │   ├── Caja.razor                         # Módulo de arqueos y turnos de caja
│   │   ├── Inventario.razor                   # Control de inventario con exportación Excel
│   │   ├── Reportes.razor                     # Métricas y últimas 10 ventas con exportación Excel
│   │   ├── Movimientos.razor                  # Auditoría del sistema con exportación Excel
│   │   ├── Categorias.razor                   # Familias de productos
│   │   ├── Usuarios.razor                     # Administración de personal y roles
│   │   ├── Configuracion.razor                # Mesas, tarifas y reservas
│   │   └── Login.razor                        # Pantalla de acceso obligatorio
│   ├── Services/                              # Servicios de negocio
│   │   ├── SupabaseService.cs                 # Conexión con Supabase, RPC y Realtime
│   │   └── ExcelExportService.cs              # Generación de reportes Excel con DocumentFormat.OpenXml
│   ├── wwwroot/
│   │   ├── appsettings.example.json           # Plantilla de configuración sin credenciales
│   │   ├── images/LogoShelbyville.png         # Isotipo oficial del club
│   │   └── index.html                         # Host WASM con helper de descarga Blob
│   ├── Program.cs                             # Inicialización y DI de la aplicación
│   └── Shelbyville.csproj                     # Configuración del proyecto .NET 10 y OpenXML
└── README.md
```

---

## 🛠️ Instalación y Puesta en Marcha

### Prerrequisitos
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) instalado.
- Una cuenta y proyecto creado en [Supabase](https://supabase.com/).

### 1. Clonar el Repositorio
```bash
git clone https://github.com/strangemarco/shelbyville.git
cd shelbyville
```

### 2. Configurar la Base de Datos en Supabase
1. Ingresa al **SQL Editor** de tu proyecto en Supabase.
2. Ejecuta los scripts ubicados en la carpeta `database/` en orden numérico:
   - `database/00_master_deploy_all.sql`
   - `database/09_modulo_gestion_mesas_tarifas_reservas.sql`
   - `database/10_modulo_usuarios_y_roles.sql`
   - `database/11_soporte_pago_mixto_pos_y_mesas.sql`
   - `database/12_fix_liquidar_sesion_mesa.sql`

### 3. Configurar Credenciales Locales
Copia la plantilla de configuración:
```bash
cp Shelbyville/wwwroot/appsettings.example.json Shelbyville/wwwroot/appsettings.json
```
Abre `Shelbyville/wwwroot/appsettings.json` y reemplaza los valores con las credenciales de tu proyecto en Supabase (obtenidas en *Project Settings > API*):
```json
{
  "Supabase": {
    "Url": "https://TU_PROYECTO.supabase.co",
    "Key": "TU_SUPABASE_ANON_KEY"
  }
}
```

> **Nota de Seguridad:** El archivo `appsettings.json` se encuentra ignorado en `.gitignore` para garantizar que tus credenciales privadas nunca sean subidas al repositorio.

### 4. Compilar y Ejecutar
Para compilar la solución:
```bash
dotnet build Shelbyville/Shelbyville.csproj
```

Para iniciar el servidor de desarrollo local:
```bash
dotnet run --project Shelbyville/Shelbyville.csproj
```
Abre tu navegador en la URL indicada en la consola (por ejemplo `https://localhost:7135` o `http://localhost:5135`).

---

## 📑 Exportaciones Excel Oficiales

Los reportes se generan utilizando **`DocumentFormat.OpenXml`**, garantizando compatibilidad 100% nativa con Microsoft Excel, Office 365, Google Sheets y LibreOffice:

| Módulo | Archivo Generado | Contenido Principal |
| :--- | :--- | :--- |
| **Inventario** | `Inventario_Shelbyville_*.xlsx` | Códigos, artículos, categorías, costos, precios de venta, márgenes, existencias, estado y valorización total. |
| **Reportes** | `Reporte_Financiero_Shelbyville_*.xlsx` | Hoja 1: Resumen de facturación por canal (Efectivo/QR/Tarjeta). Hoja 2: Listado de últimas ventas detalladas. |
| **Movimientos** | `Movimientos_Shelbyville_*.xlsx` | Bitácora operativa filtrada por módulo (Mesas, Ventas, Caja, Inventario) con importes y estados. |

---

## 💳 Flujo de Pago Mixto (Efectivo + QR)

El sistema soporta clientes que dividen el monto total de su cuenta entre efectivo y transferencia/código QR:

```
[ Total a Cobrar: Bs. 50.00 ]
           │
           ├── Parte Efectivo: Bs. 30.00
           │     └─ Cliente entrega: Bs. 50.00 ──► Vuelto/Cambio: Bs. 20.00
           │
           └── Parte QR:       Bs. 20.00 (Monto exacto transferido)
```

En la base de datos se generan dos asientos de pago auditables vinculados a la misma venta, actualizando con precisión tanto el efectivo esperado en gaveta como los ingresos digitales por QR.

---

## 📄 Licencia

Este proyecto está bajo la licencia [MIT](LICENSE).
