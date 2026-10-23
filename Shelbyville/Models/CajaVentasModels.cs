using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("cajas")]
public class CajaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("nombre")]
    public string Nombre { get; set; } = "Caja Principal";

    [Column("usuario_apertura_id")]
    public string? UsuarioAperturaId { get; set; }

    [Column("usuario_cierre_id")]
    public string? UsuarioCierreId { get; set; }

    [Column("monto_inicial")]
    public decimal MontoInicial { get; set; }

    [Column("monto_ventas_efectivo")]
    public decimal MontoVentasEfectivo { get; set; }

    [Column("monto_ventas_qr")]
    public decimal MontoVentasQr { get; set; }

    [Column("monto_ventas_tarjeta")]
    public decimal MontoVentasTarjeta { get; set; }

    [Column("monto_ingresos_extra")]
    public decimal MontoIngresosExtra { get; set; }

    [Column("monto_egresos")]
    public decimal MontoEgresos { get; set; }

    [Column("monto_esperado_efectivo")]
    public decimal MontoEsperadoEfectivo { get; set; }

    [Column("monto_real_efectivo")]
    public decimal? MontoRealEfectivo { get; set; }

    [Column("diferencia")]
    public decimal? Diferencia { get; set; }

    [Column("estado")]
    public string Estado { get; set; } = "abierta";

    [Column("hora_apertura")]
    public DateTime HoraApertura { get; set; }

    [Column("hora_cierre")]
    public DateTime? HoraCierre { get; set; }

    [Column("observaciones")]
    public string? Observaciones { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}

[Table("movimientos_caja")]
public class MovimientoCajaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("caja_id")]
    public Guid CajaId { get; set; }

    [Column("tipo")]
    public string Tipo { get; set; } = string.Empty;

    [Column("monto")]
    public decimal Monto { get; set; }

    [Column("metodo_pago")]
    public string MetodoPago { get; set; } = "efectivo";

    [Column("referencia_id")]
    public Guid? ReferenciaId { get; set; }

    [Column("descripcion")]
    public string Descripcion { get; set; } = string.Empty;

    [Column("usuario_id")]
    public string? UsuarioId { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}

[Table("ventas")]
public class VentaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("sesion_id")]
    public Guid? SesionId { get; set; }

    [Column("caja_id")]
    public Guid CajaId { get; set; }

    [Column("tipo_venta")]
    public string TipoVenta { get; set; } = "sesion_billar";

    [Column("cliente_nombre")]
    public string? ClienteNombre { get; set; }

    [Column("subtotal_tiempo")]
    public decimal SubtotalTiempo { get; set; }

    [Column("subtotal_productos")]
    public decimal SubtotalProductos { get; set; }

    [Column("descuento")]
    public decimal Descuento { get; set; }

    [Column("total")]
    public decimal Total { get; set; }

    [Column("estado")]
    public string Estado { get; set; } = "pagada";

    [Column("usuario_id")]
    public string? UsuarioId { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}

[Table("detalles_venta")]
public class DetalleVentaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("venta_id")]
    public Guid VentaId { get; set; }

    [Column("producto_id")]
    public Guid? ProductoId { get; set; }

    [Column("concepto")]
    public string Concepto { get; set; } = string.Empty;

    [Column("cantidad")]
    public int Cantidad { get; set; } = 1;

    [Column("precio_unitario")]
    public decimal PrecioUnitario { get; set; }

    [Column("subtotal")]
    public decimal Subtotal { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}

[Table("pagos")]
public class PagoModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("venta_id")]
    public Guid VentaId { get; set; }

    [Column("caja_id")]
    public Guid CajaId { get; set; }

    [Column("metodo_pago")]
    public string MetodoPago { get; set; } = "efectivo";

    [Column("monto")]
    public decimal Monto { get; set; }

    [Column("monto_recibido")]
    public decimal? MontoRecibido { get; set; }

    [Column("cambio")]
    public decimal Cambio { get; set; }

    [Column("referencia_comprobante")]
    public string? ReferenciaComprobante { get; set; }

    [Column("usuario_id")]
    public string? UsuarioId { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}

[Table("perfiles")]
public class PerfilModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("rol_id")]
    public string RolId { get; set; } = "cajero";

    [Column("nombre_completo")]
    public string NombreCompleto { get; set; } = string.Empty;

    [Column("email")]
    public string? Email { get; set; }

    [Column("telefono")]
    public string? Telefono { get; set; }

    [Column("activo")]
    public bool Activo { get; set; } = true;

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    [Column("actualizado_en")]
    public DateTime ActualizadoEn { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public RoleModel? Rol { get; set; }
}

[Table("roles")]
public class RoleModel : BaseModel
{
    [PrimaryKey("id", false)]
    public string Id { get; set; } = string.Empty;

    [Column("nombre")]
    public string Nombre { get; set; } = string.Empty;

    [Column("descripcion")]
    public string? Descripcion { get; set; }
}
