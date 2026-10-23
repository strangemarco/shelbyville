using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("mesas")]
public class MesaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("numero")]
    public int Numero { get; set; }

    [Column("nombre")]
    public string Nombre { get; set; } = string.Empty;

    [Column("tipo")]
    public string Tipo { get; set; } = "Pool";

    [Column("tarifa_defecto_id")]
    public Guid? TarifaDefectoId { get; set; }

    [Column("estado")]
    public string Estado { get; set; } = "disponible";

    [Column("activa")]
    public bool Activa { get; set; } = true;

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    [Column("actualizado_en")]
    public DateTime ActualizadoEn { get; set; }

    // Propiedades en memoria para la interfaz
    [System.Text.Json.Serialization.JsonIgnore]
    public SesionBillarModel? SesionActiva { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public ReservaMesaModel? ReservaActiva { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public TarifaModel? Tarifa { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string TiempoTranscurridoStr { get; set; } = "00:00:00";

    [System.Text.Json.Serialization.JsonIgnore]
    public decimal MontoTiempoCalculado { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public decimal MontoTotalCalculado => MontoTiempoCalculado + (SesionActiva?.MontoConsumos ?? 0);
}
