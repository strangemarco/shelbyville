using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("consumos_mesa")]
public class ConsumoMesaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("sesion_id")]
    public Guid SesionId { get; set; }

    [Column("producto_id")]
    public Guid ProductoId { get; set; }

    [Column("cantidad")]
    public int Cantidad { get; set; }

    [Column("precio_unitario")]
    public decimal PrecioUnitario { get; set; }

    [Column("subtotal")]
    public decimal Subtotal { get; set; }

    [Column("estado")]
    public string Estado { get; set; } = "confirmado";

    [Column("motivo_anulacion")]
    public string? MotivoAnulacion { get; set; }

    [Column("usuario_id")]
    public string? UsuarioId { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    // Objeto en memoria
    [System.Text.Json.Serialization.JsonIgnore]
    public ProductoModel? Producto { get; set; }
}

[Table("movimientos_inventario")]
public class MovimientoInventarioModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("producto_id")]
    public Guid ProductoId { get; set; }

    [Column("tipo")]
    public string Tipo { get; set; } = string.Empty;

    [Column("cantidad")]
    public int Cantidad { get; set; }

    [Column("stock_anterior")]
    public int StockAnterior { get; set; }

    [Column("stock_nuevo")]
    public int StockNuevo { get; set; }

    [Column("referencia_id")]
    public Guid? ReferenciaId { get; set; }

    [Column("motivo")]
    public string? Motivo { get; set; }

    [Column("usuario_id")]
    public string? UsuarioId { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}
