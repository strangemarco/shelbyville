using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("categorias")]
public class CategoriaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("nombre")]
    public string Nombre { get; set; } = string.Empty;

    [Column("descripcion")]
    public string? Descripcion { get; set; }

    [Column("icono")]
    public string? Icono { get; set; } = "Layers";

    [Column("orden")]
    public int Orden { get; set; }

    [Column("activo")]
    public bool Activo { get; set; } = true;

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}

[Table("productos")]
public class ProductoModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("categoria_id")]
    public Guid? CategoriaId { get; set; }

    [Column("codigo")]
    public string? Codigo { get; set; }

    [Column("nombre")]
    public string Nombre { get; set; } = string.Empty;

    [Column("descripcion")]
    public string? Descripcion { get; set; }

    [Column("precio_compra")]
    public decimal PrecioCompra { get; set; }

    [Column("precio_venta")]
    public decimal PrecioVenta { get; set; }

    [Column("stock")]
    public int Stock { get; set; }

    [Column("stock_minimo")]
    public int StockMinimo { get; set; } = 5;

    [Column("activo")]
    public bool Activo { get; set; } = true;

    [Column("imagen_url")]
    public string? ImagenUrl { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    [Column("actualizado_en")]
    public DateTime ActualizadoEn { get; set; }

    // Propiedad en memoria
    public bool StockBajo => Stock <= StockMinimo;
}
