using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Shelbyville.Models;

[Table("vista_movimientos_sistema")]
public class MovimientoSistemaModel : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("modulo")]
    public string Modulo { get; set; } = string.Empty;

    [Column("tipo")]
    public string Tipo { get; set; } = string.Empty;

    [Column("titulo")]
    public string Titulo { get; set; } = string.Empty;

    [Column("detalle")]
    public string Detalle { get; set; } = string.Empty;

    [Column("monto")]
    public decimal? Monto { get; set; }

    [Column("estado")]
    public string Estado { get; set; } = string.Empty;

    [Column("usuario")]
    public string? Usuario { get; set; }

    [Column("fecha")]
    public DateTime Fecha { get; set; }
}
