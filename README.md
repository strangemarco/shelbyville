# 🎱 Shelbyville Billiard Club - Management System

Sistema integral de gestión, control de tiempos de billar, punto de venta (POS) y arqueo de caja desarrollado con tecnologías web modernas de alto rendimiento.

Diseñado específicamente para clubes de billar, bares y salas de entretenimiento que requieren control riguroso de mesas por tiempo, venta de productos en mostrador, arqueos de caja transparentes y opciones de pago flexibles (Efectivo, QR y Pagos Mixtos).

---

## 🚀 Tecnologías Principales

- **Frontend:** [.NET 10 Blazor WebAssembly](https://dotnet.microsoft.com/apps/aspnet/web-apps/blazor) (SPA de alto rendimiento en el navegador)
- **Componentes UI:** [MudBlazor 9](https://mudblazor.com/) (Material Design personalizado con temática Luxury Billiard)
- **Backend & Base de Datos:** [Supabase](https://supabase.com/)
  - **PostgreSQL 15+** con lógica de negocio encapsulada en funciones PL/pgSQL transaccionales (RPC)
  - **GoTrue Auth:** Autenticación segura de usuarios
  - **Supabase Realtime:** Sincronización en vivo del estado de las mesas entre dispositivos
- **Tipografía y Estilo:** Google Fonts (*Outfit* para encabezados y *Inter* para datos numéricos y tablas), tema de lujo verde billar (`#0B1210`, `#164F3B`) y acentos dorados (`#D4AF37`).

---

## ✨ Características y Módulos

### 1. 🎱 Control de Mesas de Billar
- **Monitoreo en Tiempo Real:** Visualización del estado de cada mesa (*Disponible*, *Ocupada*, *Pausada*, *Mantenimiento*).
- **Cronómetro de Juego:** Cálculo automático del tiempo transcurrido y tarifa por hora o fracción de minuto.
- **Consumos a la Mesa:** Posibilidad de cargar bebidas, botanas o consumos de barra directamente a la cuenta de la mesa con descuento inmediato de inventario.
- **Liquidación y Cobro:**
  - Resumen detallado de tiempo jugado + consumos de barra.
  - Aplicación de descuentos especiales.
  - Métodos de pago: **Efectivo**, **QR** y **Mixto (Efectivo + QR)**.
  - Cálculo automático de desglose, efectivo entregado y vuelto/cambio.
  - Liberación física de la mesa y registro del comprobante de venta.

### 2. 🛒 Punto de Venta Mostrador (POS)
- Venta directa ágil para clientes en barra o mostrador sin ocupar mesa.
- Búsqueda predictiva de productos por nombre o código.
- Filtro dinámico por categorías.
- Carrito de compras interactivo con validación de stock en tiempo real.
- Aplicación de descuentos.
- **Soporte de Pago Mixto:** Desglose configurable de parte en efectivo y parte en QR con cálculo instantáneo de vuelto.
- Función de derivar pedidos del carrito directamente a una mesa activa.

### 3. 💵 Gestión y Arqueo de Caja
- **Apertura de Caja:** Registro de monto inicial y asignación de cajero.
- **Discriminación Contable:**
  - Ventas en Efectivo (Mesas + Mostrador).
  - Ventas por QR (Mesas + Mostrador).
  - Pagos mixtos desglosados auditables.
  - Egresos y gastos operativos.
  - Ajustes manuales justificados.
- **Cierre y Arqueo:** Comparativa automática entre monto esperado y monto real ingresado con cálculo de descuadre (*Faltante* o *Sobrante*).
- Historial completo y movimientos detallados para auditoría.

### 4. 📦 Inventario y KARDEX
- Catálogo de productos con precios de compra, precios de venta y control de stock.
- Alertas visuales de stock mínimo y productos agotados.
- Registro automatizado de movimientos de inventario (KARDEX) en cada venta, consumo o anulación.
- Paginación moderna y responsiva.

### 5. 👥 Usuarios, Roles y Seguridad
- Roles predefinidos: **Administrador**, **Cajero** y **Mozo**.
- Creación de usuarios con contraseñas seguras mediante funciones administrativas en Supabase.
- Restablecimiento y cambio de contraseñas desde el panel de administración.
- Persistencia de sesión segura en navegador (`localStorage`) para evitar desconexiones accidentales al refrescar la página.
- Botón de cierre de sesión seguro en el menú de navegación.

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
│   ├── 10_modulo_usuarios_y_roles.sql         # Gestión administrativa de usuarios y roles
│   └── 11_soporte_pago_mixto_pos_y_mesas.sql  # Soporte integral de pagos mixtos (Efectivo + QR)
├── Shelbyville/                               # Aplicación Blazor WebAssembly
│   ├── Components/                            # Modales y componentes reutilizables
│   │   ├── ModalCobroMesa.razor               # Modal de liquidación de mesas con soporte mixto
│   │   ├── ModalAperturaCaja.razor            # Modal de inicio de jornada de caja
│   │   ├── ModalCierreCaja.razor              # Modal de arqueo y cierre
│   │   ├── ModalGastoCaja.razor               # Modal de registro de egresos
│   │   ├── ModalProducto.razor                # Modal de creación/edición de productos
│   │   ├── ModalUsuario.razor                 # Modal de gestión de personal
│   │   └── ModalPasswordUsuario.razor         # Modal de reseteo de contraseñas
│   ├── Layout/                                # Layouts principales de la app
│   │   ├── MainLayout.razor                   # Layout principal con navegación y badge de usuario
│   │   ├── NavMenu.razor                      # Barra lateral de módulos
│   │   └── EmptyLayout.razor                  # Layout limpio para Login
│   ├── Models/                                # Modelos de datos y mapeos Supabase C#
│   ├── Pages/                                 # Vistas principales del sistema
│   │   ├── Dashboard.razor                    # Métricas de ocupación y ventas del día
│   │   ├── Mesas.razor                        # Tablero de control de mesas de billar
│   │   ├── Pos.razor                          # Punto de venta mostrador
│   │   ├── Caja.razor                         # Módulo de arqueos y movimientos de caja
│   │   ├── Productos.razor                    # Catálogo e inventario
│   │   ├── Movimientos.razor                  # Auditoría de transacciones
│   │   ├── Usuarios.razor                     # Administración de personal y roles
│   │   ├── Configuracion.razor                # Tarifas de billar y parámetros del club
│   │   └── Login.razor                        # Inicio de sesión con diseño estilizado
│   ├── Services/                              # Lógica de comunicación con Supabase
│   │   └── SupabaseService.cs                 # Servicio singleton cliente Supabase
│   ├── wwwroot/
│   │   ├── appsettings.example.json           # Plantilla de configuración sin credenciales
│   │   └── css/app.css                        # Estilos globales y tokens del tema
│   ├── Program.cs                             # Inicialización y DI de la aplicación
│   └── Shelbyville.csproj                     # Configuración del proyecto .NET 10
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
2. Ejecuta los scripts ubicados en la carpeta `database/` en orden numérico, o ejecuta directamente:
   - `database/00_master_deploy_all.sql`
   - `database/10_modulo_usuarios_y_roles.sql`
   - `database/11_soporte_pago_mixto_pos_y_mesas.sql`

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

> **Nota de Seguridad:** El archivo `appsettings.json` se encuentra ignorado en `.gitignore` para garantizar que tus credenciales privadas nunca sean subidas a repositorios públicos.

### 4. Compilar y Ejecutar
Para compilar la solución:
```bash
cd Shelbyville
dotnet build
```

Para iniciar el servidor de desarrollo local:
```bash
dotnet run
```
Abre tu navegador en la URL que indique la consola (generalmente `https://localhost:7000` o `http://localhost:5000`).

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
