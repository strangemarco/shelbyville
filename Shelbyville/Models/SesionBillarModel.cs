using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("sesiones_billar")]
public class SesionBillarModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("mesa_id")]
    public Guid MesaId { get; set; }

    [Column("tarifa_id")]
    public Guid TarifaId { get; set; }

    [Column("cliente_nombre")]
    public string? ClienteNombre { get; set; }

    [Column("hora_inicio")]
    public DateTime HoraInicio { get; set; }

    [Column("hora_fin")]
    public DateTime? HoraFin { get; set; }

    [Column("segundos_pausados")]
    public int SegundosPausados { get; set; }

    [Column("minutos_cobrables")]
    public int MinutosCobrables { get; set; }

    [Column("monto_tiempo")]
    public decimal MontoTiempo { get; set; }

    [Column("monto_consumos")]
    public decimal MontoConsumos { get; set; }

    [Column("monto_descuento")]
    public decimal MontoDescuento { get; set; }

    [Column("monto_total")]
    public decimal MontoTotal { get; set; }

    [Column("estado")]
    public string Estado { get; set; } = "activa";

    [Column("usuario_inicio_id")]
    public string? UsuarioInicioId { get; set; }

    [Column("usuario_cierre_id")]
    public string? UsuarioCierreId { get; set; }

    [Column("notas")]
    public string? Notas { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }

    [Column("actualizado_en")]
    public DateTime ActualizadoEn { get; set; }

    // Propiedad en memoria para congelar el cronómetro durante la pausa activa
    public DateTime? PausaActivaInicio { get; set; }
}

[Table("pausas_sesion")]
public class PausaSesionModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("sesion_id")]
    public Guid SesionId { get; set; }

    [Column("hora_inicio")]
    public DateTime HoraInicio { get; set; }

    [Column("hora_fin")]
    public DateTime? HoraFin { get; set; }

    [Column("duracion_segundos")]
    public int? DuracionSegundos { get; set; }

    [Column("motivo")]
    public string? Motivo { get; set; }

    [Column("creado_en")]
    public DateTime CreadoEn { get; set; }
}
