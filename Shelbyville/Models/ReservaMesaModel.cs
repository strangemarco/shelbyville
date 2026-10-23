using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("reservas_mesa")]
public class ReservaMesaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("mesa_id")]
    public Guid MesaId { get; set; }

    [Column("cliente_nombre")]
    public string ClienteNombre { get; set; } = string.Empty;

    [Column("telefono")]
    public string? Telefono { get; set; }

    [Column("fecha")]
    public DateTime Fecha { get; set; }

    [Column("hora_inicio")]
    public string HoraInicio { get; set; } = string.Empty;

    [Column("hora_fin")]
    public string HoraFin { get; set; } = string.Empty;

    [Column("inicio_utc")]
    public DateTime InicioUtc { get; set; }

    [Column("fin_utc")]
    public DateTime FinUtc { get; set; }

    [Column("minutos_tolerancia_llegada")]
    public int MinutosToleranciaLlegada { get; set; } = 15;

    [Column("estado")]
    public string Estado { get; set; } = "activa";

    [Column("notas")]
    public string? Notas { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    // Propiedad en memoria
    [System.Text.Json.Serialization.JsonIgnore]
    public MesaModel? Mesa { get; set; }
}
