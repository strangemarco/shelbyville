using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;
using Shelbyville;
using Shelbyville.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddScoped(sp => new HttpClient { BaseAddress = new Uri(builder.HostEnvironment.BaseAddress) });
builder.Services.AddMudServices();
builder.Services.AddSingleton<SupabaseService>();
builder.Services.AddScoped<ExcelExportService>();

var host = builder.Build();

// Inicializar cliente Supabase al arrancar
try
{
    var supabaseService = host.Services.GetRequiredService<SupabaseService>();
    await supabaseService.InitializeAsync();
}
catch (Exception ex)
{
    Console.WriteLine($"Error inicializando Supabase en Program.cs: {ex.Message}");
}

await host.RunAsync();
