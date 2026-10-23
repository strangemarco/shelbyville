using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("tarifas")]
public class TarifaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("nombre")]
    public string Nombre { get; set; } = string.Empty;

    [Column("descripcion")]
    public string? Descripcion { get; set; }

    [Column("precio_por_hora")]
    public decimal PrecioPorHora { get; set; }

    [Column("minutos_minimo")]
    public int MinutosMinimo { get; set; } = 15;

    [Column("minutos_tolerancia")]
    public int MinutosTolerancia { get; set; } = 5;

    [Column("activo")]
    public bool Activo { get; set; } = true;

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    [Column("actualizado_en")]
    public DateTime ActualizadoEn { get; set; }
}
