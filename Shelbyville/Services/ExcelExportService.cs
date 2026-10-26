using System.Globalization;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Spreadsheet;
using Microsoft.JSInterop;
using Shelbyville.Models;

namespace Shelbyville.Services;

public class ExcelExportService
{
    private readonly IJSRuntime _jsRuntime;

    public ExcelExportService(IJSRuntime jsRuntime)
    {
        _jsRuntime = jsRuntime;
    }

    /// <summary>
    /// Descarga los bytes generados en el navegador mediante el helper JS nativo con Blob.
    /// </summary>
    public async Task DescargarExcelAsync(byte[] bytes, string nombreArchivo)
    {
        var base64 = Convert.ToBase64String(bytes);
        await _jsRuntime.InvokeVoidAsync("shelbyvilleDescargarExcel", nombreArchivo, base64);
    }

    // =========================================================================
    // 1. EXPORTACIÓN DE INVENTARIO
    // =========================================================================
    public async Task ExportarInventarioAsync(List<ProductoModel> productos, List<CategoriaModel> categorias)
    {
        var dictCategorias = categorias.ToDictionary(c => c.Id, c => c.Nombre);

        using var memoryStream = new MemoryStream();
        using (var document = SpreadsheetDocument.Create(memoryStream, SpreadsheetDocumentType.Workbook))
        {
            var workbookPart = document.AddWorkbookPart();
            workbookPart.Workbook = new Workbook();

            var stylesPart = workbookPart.AddNewPart<WorkbookStylesPart>();
            stylesPart.Stylesheet = CreateStylesheet();
            stylesPart.Stylesheet.Save();

            var worksheetPart = workbookPart.AddNewPart<WorksheetPart>();
            var worksheet = new Worksheet();

            // Configuración de anchos de columna
            var columns = new Columns();
            columns.Append(CreateColumn(1, 1, 14)); // Código
            columns.Append(CreateColumn(2, 2, 32)); // Artículo
            columns.Append(CreateColumn(3, 3, 20)); // Categoría
            columns.Append(CreateColumn(4, 4, 16)); // Costo Compra
            columns.Append(CreateColumn(5, 5, 16)); // Precio Venta
            columns.Append(CreateColumn(6, 6, 14)); // Margen Bruto
            columns.Append(CreateColumn(7, 7, 14)); // Stock Mínimo
            columns.Append(CreateColumn(8, 8, 14)); // Stock Actual
            columns.Append(CreateColumn(9, 9, 16)); // Estado Stock
            columns.Append(CreateColumn(10, 10, 20)); // Valorización Total
            worksheet.Append(columns);

            var sheetData = new SheetData();

            // Fila 1: Título Principal
            var row1 = new Row();
            row1.Append(CreateTextCell("SHELBYVILLE BILLIARD CLUB - CONTROL DE INVENTARIO Y STOCK", 1));
            sheetData.Append(row1);

            // Fila 2: Subtítulo / Metadatos
            var row2 = new Row();
            row2.Append(CreateTextCell($"Generado: {DateTime.Now:dd/MM/yyyy HH:mm:ss} | Total Artículos: {productos.Count}", 2));
            sheetData.Append(row2);

            // Fila 3: Vacía de separación
            sheetData.Append(new Row());

            // Fila 4: Encabezados de Tabla
            var headerRow = new Row();
            headerRow.Append(CreateTextCell("CÓDIGO", 3));
            headerRow.Append(CreateTextCell("ARTÍCULO / PRODUCTO", 4));
            headerRow.Append(CreateTextCell("CATEGORÍA", 4));
            headerRow.Append(CreateTextCell("COSTO COMPRA (Bs.)", 5));
            headerRow.Append(CreateTextCell("PRECIO VENTA (Bs.)", 5));
            headerRow.Append(CreateTextCell("MARGEN (Bs.)", 5));
            headerRow.Append(CreateTextCell("STOCK MÍNIMO", 3));
            headerRow.Append(CreateTextCell("STOCK ACTUAL", 3));
            headerRow.Append(CreateTextCell("ESTADO", 3));
            headerRow.Append(CreateTextCell("VALOR TOTAL (Bs.)", 5));
            sheetData.Append(headerRow);

            // Filas de Datos
            decimal totalValorInventario = 0;
            int totalUnidades = 0;

            foreach (var p in productos)
            {
                var row = new Row();
                var categoriaNombre = p.CategoriaId.HasValue && dictCategorias.TryGetValue(p.CategoriaId.Value, out var cat) ? cat : "Sin categoría";
                var valorArticulo = p.Stock * p.PrecioCompra;
                var margen = p.PrecioVenta - p.PrecioCompra;
                var estado = p.Stock <= 0 ? "Agotado" : (p.StockBajo ? "Stock Crítico" : "Normal");

                totalValorInventario += valorArticulo;
                totalUnidades += p.Stock;

                row.Append(CreateTextCell(p.Codigo ?? "-", 7));
                row.Append(CreateTextCell(p.Nombre, 6));
                row.Append(CreateTextCell(categoriaNombre, 6));
                row.Append(CreateNumberCell(p.PrecioCompra, 8));
                row.Append(CreateNumberCell(p.PrecioVenta, 8));
                row.Append(CreateNumberCell(margen, 8));
                row.Append(CreateNumberCell(p.StockMinimo, 7));
                row.Append(CreateNumberCell(p.Stock, 7));
                row.Append(CreateTextCell(estado, 7));
                row.Append(CreateNumberCell(valorArticulo, 8));

                sheetData.Append(row);
            }

            // Fila de Totales
            var totalRow = new Row();
            totalRow.Append(CreateTextCell("TOTALES GENERALES", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateNumberCell(totalUnidades, 9));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateNumberCell(totalValorInventario, 9));
            sheetData.Append(totalRow);

            worksheet.Append(sheetData);
            worksheetPart.Worksheet = worksheet;
            worksheetPart.Worksheet.Save();

            var sheets = workbookPart.Workbook.AppendChild(new Sheets());
            var sheet = new Sheet()
            {
                Id = workbookPart.GetIdOfPart(worksheetPart),
                SheetId = 1,
                Name = "Inventario"
            };
            sheets.Append(sheet);

            workbookPart.Workbook.Save();
        }

        var nombreArchivo = $"Inventario_Shelbyville_{DateTime.Now:yyyyMMdd_HHmm}.xlsx";
        await DescargarExcelAsync(memoryStream.ToArray(), nombreArchivo);
    }

    // =========================================================================
    // 2. EXPORTACIÓN DE REPORTES (CAJA Y FACTURACIÓN)
    // =========================================================================
    public async Task ExportarReporteFinancieroAsync(CajaModel? caja, List<MesaModel> mesas, List<VentaModel> ultimasVentas)
    {
        using var memoryStream = new MemoryStream();
        using (var document = SpreadsheetDocument.Create(memoryStream, SpreadsheetDocumentType.Workbook))
        {
            var workbookPart = document.AddWorkbookPart();
            workbookPart.Workbook = new Workbook();

            var stylesPart = workbookPart.AddNewPart<WorkbookStylesPart>();
            stylesPart.Stylesheet = CreateStylesheet();
            stylesPart.Stylesheet.Save();

            // HOJA 1: RESUMEN DE TURNO Y FACTURACIÓN
            var worksheetPart1 = workbookPart.AddNewPart<WorksheetPart>();
            var worksheet1 = new Worksheet();

            var columns1 = new Columns();
            columns1.Append(CreateColumn(1, 1, 32));
            columns1.Append(CreateColumn(2, 2, 22));
            columns1.Append(CreateColumn(3, 3, 22));
            worksheet1.Append(columns1);

            var sheetData1 = new SheetData();

            var r1 = new Row();
            r1.Append(CreateTextCell("SHELBYVILLE BILLIARD CLUB - REPORTE DE FACTURACIÓN", 1));
            sheetData1.Append(r1);

            var r2 = new Row();
            r2.Append(CreateTextCell($"Generado: {DateTime.Now:dd/MM/yyyy HH:mm:ss} | Turno: {(caja?.Nombre ?? "Sin turno activo")}", 2));
            sheetData1.Append(r2);

            sheetData1.Append(new Row());

            var hr1 = new Row();
            hr1.Append(CreateTextCell("CONCEPTO / CANAL", 4));
            hr1.Append(CreateTextCell("IMPORTE (Bs.)", 5));
            hr1.Append(CreateTextCell("PARTICIPACIÓN", 5));
            sheetData1.Append(hr1);

            decimal totalRecaudado = (caja?.MontoVentasEfectivo ?? 0) + (caja?.MontoVentasQr ?? 0) + (caja?.MontoVentasTarjeta ?? 0);
            decimal efectivo = caja?.MontoVentasEfectivo ?? 0;
            decimal qr = caja?.MontoVentasQr ?? 0;
            decimal tarjeta = caja?.MontoVentasTarjeta ?? 0;

            void AgregarFilaFinanciera(string concepto, decimal monto, decimal total)
            {
                var row = new Row();
                row.Append(CreateTextCell(concepto, 6));
                row.Append(CreateNumberCell(monto, 8));
                var pct = total > 0 ? (monto / total * 100).ToString("0.0", CultureInfo.InvariantCulture) + "%" : "0%";
                row.Append(CreateTextCell(pct, 7));
                sheetData1.Append(row);
            }

            AgregarFilaFinanciera("Cobros en Efectivo", efectivo, totalRecaudado);
            AgregarFilaFinanciera("Cobros Digitales (QR / Transferencia)", qr, totalRecaudado);
            AgregarFilaFinanciera("Cobros con Tarjeta de Débito/Crédito", tarjeta, totalRecaudado);

            var totalFinRow = new Row();
            totalFinRow.Append(CreateTextCell("TOTAL RECAUDADO EN EL TURNO", 10));
            totalFinRow.Append(CreateNumberCell(totalRecaudado, 9));
            totalFinRow.Append(CreateTextCell("100.0%", 9));
            sheetData1.Append(totalFinRow);

            sheetData1.Append(new Row());
            sheetData1.Append(new Row());

            // Métricas de operación
            var rOpTitle = new Row();
            rOpTitle.Append(CreateTextCell("DATOS DE OPERACIÓN DEL TURNO", 1));
            sheetData1.Append(rOpTitle);

            void AgregarMetricaOperacion(string metrica, string valor)
            {
                var row = new Row();
                row.Append(CreateTextCell(metrica, 6));
                row.Append(CreateTextCell(valor, 7));
                row.Append(CreateTextCell("", 6));
                sheetData1.Append(row);
            }

            AgregarMetricaOperacion("Fondo Inicial de Apertura", $"Bs. {(caja?.MontoInicial ?? 0):N2}");
            AgregarMetricaOperacion("Hora de Apertura de Caja", caja?.HoraApertura.ToLocalTime().ToString("dd/MM/yyyy HH:mm") ?? "-");
            AgregarMetricaOperacion("Total de Mesas en Salón", $"{mesas.Count} mesas");
            AgregarMetricaOperacion("Mesas Ocupadas Actualmente", $"{mesas.Count(m => m.Estado == "ocupada")} mesas");
            AgregarMetricaOperacion("Porcentaje de Ocupación", mesas.Count > 0 ? $"{(double)mesas.Count(m => m.Estado == "ocupada") / mesas.Count * 100:0}%" : "0%");

            worksheet1.Append(sheetData1);
            worksheetPart1.Worksheet = worksheet1;
            worksheetPart1.Worksheet.Save();

            // HOJA 2: ÚLTIMAS VENTAS DETALLADAS
            var worksheetPart2 = workbookPart.AddNewPart<WorksheetPart>();
            var worksheet2 = new Worksheet();

            var columns2 = new Columns();
            columns2.Append(CreateColumn(1, 1, 13)); // Fecha
            columns2.Append(CreateColumn(2, 2, 11)); // Hora
            columns2.Append(CreateColumn(3, 3, 18)); // Tipo
            columns2.Append(CreateColumn(4, 4, 25)); // Cliente
            columns2.Append(CreateColumn(5, 5, 16)); // Tiempo Mesa
            columns2.Append(CreateColumn(6, 6, 16)); // Consumos
            columns2.Append(CreateColumn(7, 7, 14)); // Descuento
            columns2.Append(CreateColumn(8, 8, 20)); // Método de Pago
            columns2.Append(CreateColumn(9, 9, 16)); // Total
            columns2.Append(CreateColumn(10, 10, 14)); // Estado
            worksheet2.Append(columns2);

            var sheetData2 = new SheetData();

            var vTitle = new Row();
            vTitle.Append(CreateTextCell("ÚLTIMAS VENTAS Y LIQUIDACIONES REGISTRADAS", 1));
            sheetData2.Append(vTitle);

            var vSub = new Row();
            vSub.Append(CreateTextCell($"Total transacciones listadas: {ultimasVentas.Count}", 2));
            sheetData2.Append(vSub);

            sheetData2.Append(new Row());

            var vHeader = new Row();
            vHeader.Append(CreateTextCell("FECHA", 3));
            vHeader.Append(CreateTextCell("HORA", 3));
            vHeader.Append(CreateTextCell("TIPO OPERACIÓN", 4));
            vHeader.Append(CreateTextCell("CLIENTE", 4));
            vHeader.Append(CreateTextCell("TIEMPO MESA (Bs.)", 5));
            vHeader.Append(CreateTextCell("CONSUMOS (Bs.)", 5));
            vHeader.Append(CreateTextCell("DESCUENTO (Bs.)", 5));
            vHeader.Append(CreateTextCell("MÉTODO DE PAGO", 3));
            vHeader.Append(CreateTextCell("TOTAL (Bs.)", 5));
            vHeader.Append(CreateTextCell("ESTADO", 3));
            sheetData2.Append(vHeader);

            decimal sumaVentas = 0;
            foreach (var v in ultimasVentas)
            {
                var row = new Row();
                var tipo = (v.TipoVenta == "mesa" || v.TipoVenta == "sesion_billar") ? "Mesa de Billar" : "Venta Directa POS";
                sumaVentas += v.Total;

                row.Append(CreateTextCell(v.CreadoEn.ToLocalTime().ToString("dd/MM/yyyy"), 7));
                row.Append(CreateTextCell(v.CreadoEn.ToLocalTime().ToString("HH:mm:ss"), 7));
                row.Append(CreateTextCell(tipo, 6));
                row.Append(CreateTextCell(v.ClienteNombre ?? "Cliente Mostrador", 6));
                row.Append(CreateNumberCell(v.SubtotalTiempo, 8));
                row.Append(CreateNumberCell(v.SubtotalProductos, 8));
                row.Append(CreateNumberCell(v.Descuento, 8));
                row.Append(CreateTextCell(v.MetodoPagoPrincipal, 7));
                row.Append(CreateNumberCell(v.Total, 8));
                row.Append(CreateTextCell(v.Estado.ToUpperInvariant(), 7));

                sheetData2.Append(row);
            }

            var totalVentasRow = new Row();
            totalVentasRow.Append(CreateTextCell("TOTAL VENTAS LISTADAS", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateTextCell("", 10));
            totalVentasRow.Append(CreateNumberCell(sumaVentas, 9));
            totalVentasRow.Append(CreateTextCell("", 10));
            sheetData2.Append(totalVentasRow);

            worksheet2.Append(sheetData2);
            worksheetPart2.Worksheet = worksheet2;
            worksheetPart2.Worksheet.Save();

            // Registro de las dos hojas en el libro
            var sheets = workbookPart.Workbook.AppendChild(new Sheets());
            sheets.Append(new Sheet()
            {
                Id = workbookPart.GetIdOfPart(worksheetPart1),
                SheetId = 1,
                Name = "Resumen Financiero"
            });
            sheets.Append(new Sheet()
            {
                Id = workbookPart.GetIdOfPart(worksheetPart2),
                SheetId = 2,
                Name = "Últimas Ventas"
            });

            workbookPart.Workbook.Save();
        }

        var nombreArchivo = $"Reporte_Financiero_Shelbyville_{DateTime.Now:yyyyMMdd_HHmm}.xlsx";
        await DescargarExcelAsync(memoryStream.ToArray(), nombreArchivo);
    }

    // =========================================================================
    // 3. EXPORTACIÓN DE MOVIMIENTOS Y AUDITORÍA
    // =========================================================================
    public async Task ExportarMovimientosAsync(List<MovimientoSistemaModel> movimientos, string filtroModulo)
    {
        using var memoryStream = new MemoryStream();
        using (var document = SpreadsheetDocument.Create(memoryStream, SpreadsheetDocumentType.Workbook))
        {
            var workbookPart = document.AddWorkbookPart();
            workbookPart.Workbook = new Workbook();

            var stylesPart = workbookPart.AddNewPart<WorkbookStylesPart>();
            stylesPart.Stylesheet = CreateStylesheet();
            stylesPart.Stylesheet.Save();

            var worksheetPart = workbookPart.AddNewPart<WorksheetPart>();
            var worksheet = new Worksheet();

            var columns = new Columns();
            columns.Append(CreateColumn(1, 1, 13)); // Fecha
            columns.Append(CreateColumn(2, 2, 11)); // Hora
            columns.Append(CreateColumn(3, 3, 16)); // Módulo
            columns.Append(CreateColumn(4, 4, 18)); // Tipo Operación
            columns.Append(CreateColumn(5, 5, 28)); // Título
            columns.Append(CreateColumn(6, 6, 46)); // Detalles
            columns.Append(CreateColumn(7, 7, 16)); // Importe (Bs.)
            columns.Append(CreateColumn(8, 8, 14)); // Estado
            worksheet.Append(columns);

            var sheetData = new SheetData();

            var r1 = new Row();
            r1.Append(CreateTextCell("SHELBYVILLE BILLIARD CLUB - AUDITORÍA Y MOVIMIENTOS", 1));
            sheetData.Append(r1);

            var r2 = new Row();
            r2.Append(CreateTextCell($"Generado: {DateTime.Now:dd/MM/yyyy HH:mm:ss} | Filtro: {filtroModulo.ToUpper()} | Total Registros: {movimientos.Count}", 2));
            sheetData.Append(r2);

            sheetData.Append(new Row());

            var hr = new Row();
            hr.Append(CreateTextCell("FECHA", 3));
            hr.Append(CreateTextCell("HORA", 3));
            hr.Append(CreateTextCell("MÓDULO", 4));
            hr.Append(CreateTextCell("TIPO", 4));
            hr.Append(CreateTextCell("TÍTULO", 4));
            hr.Append(CreateTextCell("DETALLES DE LA OPERACIÓN", 4));
            hr.Append(CreateTextCell("IMPORTE (Bs.)", 5));
            hr.Append(CreateTextCell("ESTADO", 3));
            sheetData.Append(hr);

            decimal totalMonto = 0;
            foreach (var m in movimientos)
            {
                var row = new Row();
                if (m.Monto.HasValue)
                {
                    totalMonto += m.Monto.Value;
                }

                row.Append(CreateTextCell(m.Fecha.ToLocalTime().ToString("dd/MM/yyyy"), 7));
                row.Append(CreateTextCell(m.Fecha.ToLocalTime().ToString("HH:mm:ss"), 7));
                row.Append(CreateTextCell(m.Modulo, 6));
                row.Append(CreateTextCell(m.Tipo, 6));
                row.Append(CreateTextCell(m.Titulo, 6));
                row.Append(CreateTextCell(m.Detalle, 6));
                row.Append(m.Monto.HasValue ? CreateNumberCell(m.Monto.Value, 8) : CreateTextCell("-", 7));
                row.Append(CreateTextCell(m.Estado, 7));

                sheetData.Append(row);
            }

            var totalRow = new Row();
            totalRow.Append(CreateTextCell("MONTO TOTAL OPERADO", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateNumberCell(totalMonto, 9));
            totalRow.Append(CreateTextCell("", 10));
            sheetData.Append(totalRow);

            worksheet.Append(sheetData);
            worksheetPart.Worksheet = worksheet;
            worksheetPart.Worksheet.Save();

            var sheets = workbookPart.Workbook.AppendChild(new Sheets());
            sheets.Append(new Sheet()
            {
                Id = workbookPart.GetIdOfPart(worksheetPart),
                SheetId = 1,
                Name = "Movimientos"
            });

            workbookPart.Workbook.Save();
        }

        var nombreArchivo = $"Movimientos_Shelbyville_{DateTime.Now:yyyyMMdd_HHmm}.xlsx";
        await DescargarExcelAsync(memoryStream.ToArray(), nombreArchivo);
    }

    // =========================================================================
    // 4. EXPORTACIÓN DE HISTORIAL DE CAJAS Y ARQUEOS
    // =========================================================================
    public async Task ExportarHistorialCajasAsync(List<CajaModel> cajas, List<PerfilModel> perfiles)
    {
        var dictPerfiles = perfiles.Where(p => !string.IsNullOrWhiteSpace(p.NombreCompleto))
                                  .ToDictionary(p => p.Id.ToString().ToLowerInvariant(), p => p.NombreCompleto);

        using var memoryStream = new MemoryStream();
        using (var document = SpreadsheetDocument.Create(memoryStream, SpreadsheetDocumentType.Workbook))
        {
            var workbookPart = document.AddWorkbookPart();
            workbookPart.Workbook = new Workbook();

            var stylesPart = workbookPart.AddNewPart<WorkbookStylesPart>();
            stylesPart.Stylesheet = CreateStylesheet();
            stylesPart.Stylesheet.Save();

            var worksheetPart = workbookPart.AddNewPart<WorksheetPart>();
            var worksheet = new Worksheet();

            var columns = new Columns();
            columns.Append(CreateColumn(1, 1, 8));   // N°
            columns.Append(CreateColumn(2, 2, 28));  // Turno / Caja
            columns.Append(CreateColumn(3, 3, 18));  // Apertura
            columns.Append(CreateColumn(4, 4, 18));  // Cierre
            columns.Append(CreateColumn(5, 5, 18));  // Fondo Inicial
            columns.Append(CreateColumn(6, 6, 20));  // Ventas Efectivo
            columns.Append(CreateColumn(7, 7, 18));  // Ventas QR
            columns.Append(CreateColumn(8, 8, 22));  // Esperado Efectivo
            columns.Append(CreateColumn(9, 9, 20));  // Real Contado
            columns.Append(CreateColumn(10, 10, 18)); // Diferencia
            columns.Append(CreateColumn(11, 11, 16)); // Estado Arqueo
            columns.Append(CreateColumn(12, 12, 25)); // Responsable Cierre
            columns.Append(CreateColumn(13, 13, 40)); // Observaciones
            worksheet.Append(columns);

            var sheetData = new SheetData();

            // Fila 1: Título Principal
            var r1 = new Row();
            r1.Append(CreateTextCell("SHELBYVILLE BILLIARD CLUB - HISTORIAL DE TURNOS Y ARQUEOS DE CAJA", 1));
            sheetData.Append(r1);

            // Fila 2: Subtítulo / Metadatos
            var r2 = new Row();
            r2.Append(CreateTextCell($"Generado: {DateTime.Now:dd/MM/yyyy HH:mm:ss} | Total Turnos Listados: {cajas.Count}", 2));
            sheetData.Append(r2);

            sheetData.Append(new Row());

            // Fila 4: Encabezados
            var hr = new Row();
            hr.Append(CreateTextCell("N°", 3));
            hr.Append(CreateTextCell("TURNO / CAJA", 4));
            hr.Append(CreateTextCell("APERTURA", 3));
            hr.Append(CreateTextCell("CIERRE", 3));
            hr.Append(CreateTextCell("FONDO INICIAL (Bs.)", 5));
            hr.Append(CreateTextCell("VENTAS EFECTIVO (Bs.)", 5));
            hr.Append(CreateTextCell("VENTAS QR (Bs.)", 5));
            hr.Append(CreateTextCell("ESPERADO (Bs.)", 5));
            hr.Append(CreateTextCell("REAL CONTADO (Bs.)", 5));
            hr.Append(CreateTextCell("DIFERENCIA (Bs.)", 5));
            hr.Append(CreateTextCell("ESTADO ARQUEO", 3));
            hr.Append(CreateTextCell("RESPONSABLE CIERRE", 4));
            hr.Append(CreateTextCell("OBSERVACIONES / NOTAS", 4));
            sheetData.Append(hr);

            decimal totalFondoInicial = 0;
            decimal totalVentasEfectivo = 0;
            decimal totalVentasQr = 0;
            decimal totalEsperado = 0;
            decimal totalRealContado = 0;
            decimal totalDiferencia = 0;
            int num = 1;

            foreach (var c in cajas)
            {
                var row = new Row();
                var real = c.MontoRealEfectivo ?? 0;
                var dif = c.Diferencia ?? (real - c.MontoEsperadoEfectivo);
                var estadoArqueo = dif == 0 ? "Exacto" : (dif > 0 ? $"Sobrante (+{dif:N2})" : $"Faltante ({dif:N2})");

                string responsable = "Cajero";
                if (!string.IsNullOrWhiteSpace(c.UsuarioCierreId))
                {
                    var uidKey = c.UsuarioCierreId.ToLowerInvariant();
                    if (dictPerfiles.TryGetValue(uidKey, out var nombre))
                    {
                        responsable = nombre;
                    }
                }

                totalFondoInicial += c.MontoInicial;
                totalVentasEfectivo += c.MontoVentasEfectivo;
                totalVentasQr += c.MontoVentasQr;
                totalEsperado += c.MontoEsperadoEfectivo;
                totalRealContado += real;
                totalDiferencia += dif;

                row.Append(CreateNumberCell(num++, 7));
                row.Append(CreateTextCell(c.Nombre, 6));
                row.Append(CreateTextCell(c.HoraApertura.ToLocalTime().ToString("dd/MM/yyyy HH:mm"), 7));
                row.Append(CreateTextCell(c.HoraCierre.HasValue ? c.HoraCierre.Value.ToLocalTime().ToString("dd/MM/yyyy HH:mm") : "-", 7));
                row.Append(CreateNumberCell(c.MontoInicial, 8));
                row.Append(CreateNumberCell(c.MontoVentasEfectivo, 8));
                row.Append(CreateNumberCell(c.MontoVentasQr, 8));
                row.Append(CreateNumberCell(c.MontoEsperadoEfectivo, 8));
                row.Append(CreateNumberCell(real, 8));
                row.Append(CreateNumberCell(dif, 8));
                row.Append(CreateTextCell(estadoArqueo, 7));
                row.Append(CreateTextCell(responsable, 6));
                row.Append(CreateTextCell(string.IsNullOrWhiteSpace(c.Observaciones) ? "Sin notas" : c.Observaciones, 6));

                sheetData.Append(row);
            }

            // Fila de Totales
            var totalRow = new Row();
            totalRow.Append(CreateTextCell("TOTALES GENERALES", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateNumberCell(totalFondoInicial, 9));
            totalRow.Append(CreateNumberCell(totalVentasEfectivo, 9));
            totalRow.Append(CreateNumberCell(totalVentasQr, 9));
            totalRow.Append(CreateNumberCell(totalEsperado, 9));
            totalRow.Append(CreateNumberCell(totalRealContado, 9));
            totalRow.Append(CreateNumberCell(totalDiferencia, 9));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            totalRow.Append(CreateTextCell("", 10));
            sheetData.Append(totalRow);

            worksheet.Append(sheetData);
            worksheetPart.Worksheet = worksheet;
            worksheetPart.Worksheet.Save();

            var sheets = workbookPart.Workbook.AppendChild(new Sheets());
            sheets.Append(new Sheet()
            {
                Id = workbookPart.GetIdOfPart(worksheetPart),
                SheetId = 1,
                Name = "Historial Cajas"
            });

            workbookPart.Workbook.Save();
        }

        var nombreArchivo = $"Historial_Cajas_Shelbyville_{DateTime.Now:yyyyMMdd_HHmm}.xlsx";
        await DescargarExcelAsync(memoryStream.ToArray(), nombreArchivo);
    }

    // =========================================================================
    // HELPERS DE OPENXML SPREADSHEET
    // =========================================================================
    private static Column CreateColumn(uint startColumn, uint endColumn, double width)
    {
        return new Column
        {
            Min = startColumn,
            Max = endColumn,
            Width = width,
            CustomWidth = true
        };
    }

    private static Cell CreateTextCell(string text, uint styleIndex)
    {
        return new Cell
        {
            DataType = CellValues.String,
            CellValue = new CellValue(text ?? string.Empty),
            StyleIndex = styleIndex
        };
    }

    private static Cell CreateNumberCell(decimal value, uint styleIndex)
    {
        return new Cell
        {
            DataType = CellValues.Number,
            CellValue = new CellValue(value.ToString(CultureInfo.InvariantCulture)),
            StyleIndex = styleIndex
        };
    }

    private static Stylesheet CreateStylesheet()
    {
        return new Stylesheet(
            new Fonts(
                new Font( // 0: Normal
                    new FontSize() { Val = 10 },
                    new Color() { Rgb = new HexBinaryValue() { Value = "FF222222" } },
                    new FontName() { Val = "Segoe UI" }
                ),
                new Font( // 1: Header (Bold White)
                    new Bold(),
                    new FontSize() { Val = 11 },
                    new Color() { Rgb = new HexBinaryValue() { Value = "FFFFFFFF" } },
                    new FontName() { Val = "Segoe UI" }
                ),
                new Font( // 2: Title
                    new Bold(),
                    new FontSize() { Val = 14 },
                    new Color() { Rgb = new HexBinaryValue() { Value = "FF164F3B" } },
                    new FontName() { Val = "Segoe UI" }
                ),
                new Font( // 3: Subtitle / Meta
                    new Italic(),
                    new FontSize() { Val = 9.5 },
                    new Color() { Rgb = new HexBinaryValue() { Value = "FF666666" } },
                    new FontName() { Val = "Segoe UI" }
                ),
                new Font( // 4: Bold Total
                    new Bold(),
                    new FontSize() { Val = 11 },
                    new Color() { Rgb = new HexBinaryValue() { Value = "FF0B1210" } },
                    new FontName() { Val = "Segoe UI" }
                )
            ),
            new Fills(
                new Fill(new PatternFill() { PatternType = PatternValues.None }), // 0: Required None
                new Fill(new PatternFill() { PatternType = PatternValues.Gray125 }), // 1: Required Gray125
                new Fill(new PatternFill( // 2: Header Dark Green #164F3B
                    new ForegroundColor() { Rgb = new HexBinaryValue() { Value = "FF164F3B" } }
                ) { PatternType = PatternValues.Solid }),
                new Fill(new PatternFill( // 3: Gold Accent #F9F3DC
                    new ForegroundColor() { Rgb = new HexBinaryValue() { Value = "FFF9F3DC" } }
                ) { PatternType = PatternValues.Solid })
            ),
            new Borders(
                new Border( // 0: None
                    new LeftBorder(), new RightBorder(), new TopBorder(), new BottomBorder(), new DiagonalBorder()
                ),
                new Border( // 1: Thin light gray border
                    new LeftBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FFD1D5DB" } }) { Style = BorderStyleValues.Thin },
                    new RightBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FFD1D5DB" } }) { Style = BorderStyleValues.Thin },
                    new TopBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FFD1D5DB" } }) { Style = BorderStyleValues.Thin },
                    new BottomBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FFD1D5DB" } }) { Style = BorderStyleValues.Thin },
                    new DiagonalBorder()
                ),
                new Border( // 2: Double bottom border for totals
                    new LeftBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FFD1D5DB" } }) { Style = BorderStyleValues.Thin },
                    new RightBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FFD1D5DB" } }) { Style = BorderStyleValues.Thin },
                    new TopBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FF111827" } }) { Style = BorderStyleValues.Thin },
                    new BottomBorder(new Color() { Rgb = new HexBinaryValue() { Value = "FF111827" } }) { Style = BorderStyleValues.Double },
                    new DiagonalBorder()
                )
            ),
            new CellFormats(
                new CellFormat() { FontId = 0, FillId = 0, BorderId = 0 }, // 0: Normal plain
                new CellFormat() { FontId = 2, FillId = 0, BorderId = 0, ApplyFont = true }, // 1: Title
                new CellFormat() { FontId = 3, FillId = 0, BorderId = 0, ApplyFont = true }, // 2: Subtitle
                new CellFormat() { FontId = 1, FillId = 2, BorderId = 1, ApplyFont = true, ApplyFill = true, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Center, Vertical = VerticalAlignmentValues.Center } }, // 3: Table Header Center
                new CellFormat() { FontId = 1, FillId = 2, BorderId = 1, ApplyFont = true, ApplyFill = true, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Left, Vertical = VerticalAlignmentValues.Center } }, // 4: Table Header Left
                new CellFormat() { FontId = 1, FillId = 2, BorderId = 1, ApplyFont = true, ApplyFill = true, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Right, Vertical = VerticalAlignmentValues.Center } }, // 5: Table Header Right
                new CellFormat() { FontId = 0, FillId = 0, BorderId = 1, ApplyBorder = true, Alignment = new Alignment() { Vertical = VerticalAlignmentValues.Center } }, // 6: Data cell left
                new CellFormat() { FontId = 0, FillId = 0, BorderId = 1, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Center, Vertical = VerticalAlignmentValues.Center } }, // 7: Data cell center
                new CellFormat() { FontId = 0, FillId = 0, BorderId = 1, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Right, Vertical = VerticalAlignmentValues.Center } }, // 8: Data cell right
                new CellFormat() { FontId = 4, FillId = 3, BorderId = 2, ApplyFont = true, ApplyFill = true, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Right, Vertical = VerticalAlignmentValues.Center } }, // 9: Total Summary right
                new CellFormat() { FontId = 4, FillId = 3, BorderId = 2, ApplyFont = true, ApplyFill = true, ApplyBorder = true, Alignment = new Alignment() { Horizontal = HorizontalAlignmentValues.Left, Vertical = VerticalAlignmentValues.Center } } // 10: Total Summary left
            )
        );
    }
}
