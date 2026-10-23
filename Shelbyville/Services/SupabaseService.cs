using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.JSInterop;
using Shelbyville.Models;
using Supabase;

namespace Shelbyville.Services;

public class SupabaseService
{
    private readonly IConfiguration _config;
    private readonly IJSRuntime _jsRuntime;
    private Client? _client;
    private bool _initialized;
    private const string STORAGE_KEY = "shelbyville_auth_session";

    public event Action? OnMesasUpdated;
    public event Action? OnAuthStateChange;

    public SupabaseService(IConfiguration config, IJSRuntime jsRuntime)
    {
        _config = config;
        _jsRuntime = jsRuntime;
    }

    private class SessionStorageData
    {
        public string? AccessToken { get; set; }
        public string? RefreshToken { get; set; }
        public DateTime? GuardadoEn { get; set; }
    }

    public async Task GuardarSesionStorageAsync(string accessToken, string refreshToken)
    {
        try
        {
            var data = new SessionStorageData
            {
                AccessToken = accessToken,
                RefreshToken = refreshToken,
                GuardadoEn = DateTime.UtcNow
            };
            var json = JsonSerializer.Serialize(data);
            await _jsRuntime.InvokeVoidAsync("localStorage.setItem", STORAGE_KEY, json);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando sesión en localStorage: {ex.Message}");
        }
    }

    public async Task BorrarSesionStorageAsync()
    {
        try
        {
            await _jsRuntime.InvokeVoidAsync("localStorage.removeItem", STORAGE_KEY);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error borrando sesión de localStorage: {ex.Message}");
        }
    }

    public async Task<bool> RestaurarSesionAsync()
    {
        try
        {
            if (_client == null) return false;

            if (Client.Auth.CurrentUser != null && !string.IsNullOrEmpty(Client.Auth.CurrentUser.Id))
            {
                return true;
            }

            var json = await _jsRuntime.InvokeAsync<string?>("localStorage.getItem", STORAGE_KEY);
            if (string.IsNullOrWhiteSpace(json))
            {
                return false;
            }

            var data = JsonSerializer.Deserialize<SessionStorageData>(json);
            if (data == null || string.IsNullOrWhiteSpace(data.AccessToken) || string.IsNullOrWhiteSpace(data.RefreshToken))
            {
                await BorrarSesionStorageAsync();
                return false;
            }

            var session = await _client.Auth.SetSession(data.AccessToken, data.RefreshToken);
            if (session != null && session.User != null)
            {
                if (!string.IsNullOrEmpty(session.AccessToken) && !string.IsNullOrEmpty(session.RefreshToken))
                {
                    await GuardarSesionStorageAsync(session.AccessToken, session.RefreshToken);
                }

                var perfil = await GetPerfilUsuarioAsync();
                if (perfil != null && !perfil.Activo)
                {
                    await SignOutAsync();
                    return false;
                }

                OnAuthStateChange?.Invoke();
                return true;
            }

            await BorrarSesionStorageAsync();
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error restaurando sesión: {ex.Message}");
            return false;
        }
    }

    public Client Client
    {
        get
        {
            if (_client == null)
            {
                throw new InvalidOperationException("SupabaseService aún no ha sido inicializado. Llame a InitializeAsync primero.");
            }
            return _client;
        }
    }

    public async Task InitializeAsync()
    {
        if (_initialized) return;

        var url = _config["Supabase:Url"] ?? throw new InvalidOperationException("Falta Supabase:Url en appsettings.json");
        var key = _config["Supabase:Key"] ?? throw new InvalidOperationException("Falta Supabase:Key en appsettings.json");

        var options = new SupabaseOptions
        {
            AutoRefreshToken = true,
            AutoConnectRealtime = true
        };

        _client = new Client(url, key, options);
        await _client.InitializeAsync();
        _initialized = true;

        // Intentar restaurar sesión de usuario si existe en localStorage
        try
        {
            await RestaurarSesionAsync();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Aviso: No se pudo restaurar sesión en InitializeAsync: {ex.Message}");
        }

        // Intentar suscribir a Realtime
        _ = SubscribeToRealtimeAsync();
    }

    private async Task SubscribeToRealtimeAsync()
    {
        try
        {
            if (_client == null) return;
            var channel = _client.Realtime.Channel("public-mesas");
            channel.AddPostgresChangeHandler(
                Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.Inserts,
                (sender, change) => OnMesasUpdated?.Invoke()
            );
            channel.AddPostgresChangeHandler(
                Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.Updates,
                (sender, change) => OnMesasUpdated?.Invoke()
            );
            await channel.Subscribe();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error conectando Realtime: {ex.Message}");
        }
    }

    // =========================================================================
    // AUTENTICACIÓN Y PERFIL
    // =========================================================================
    public bool EstaAutenticado => Client.Auth.CurrentUser != null && !string.IsNullOrEmpty(Client.Auth.CurrentUser.Id);

    public Supabase.Gotrue.User? UsuarioActual => Client.Auth.CurrentUser;

    public async Task<(bool Exito, string? Mensaje, PerfilModel? Perfil)> IniciarSesionAsync(string email, string password)
    {
        try
        {
            var session = await Client.Auth.SignIn(email.Trim().ToLowerInvariant(), password);
            if (session == null || session.User == null)
            {
                return (false, "Credenciales incorrectas o usuario no encontrado.", null);
            }

            var perfil = await GetPerfilUsuarioAsync();
            if (perfil != null && !perfil.Activo)
            {
                await Client.Auth.SignOut();
                await BorrarSesionStorageAsync();
                return (false, "Esta cuenta ha sido desactivada por el administrador. Contacta con gerencia.", null);
            }

            if (!string.IsNullOrEmpty(session.AccessToken) && !string.IsNullOrEmpty(session.RefreshToken))
            {
                await GuardarSesionStorageAsync(session.AccessToken, session.RefreshToken);
            }

            OnAuthStateChange?.Invoke();
            return (true, null, perfil);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error de inicio de sesión: {ex.Message}");
            var errorMsg = ex.Message.Contains("Invalid login credentials", StringComparison.OrdinalIgnoreCase)
                ? "Correo electrónico o contraseña incorrectos."
                : (ex.Message.Contains("Email not confirmed", StringComparison.OrdinalIgnoreCase)
                    ? "El correo no ha sido confirmado aún en Supabase."
                    : $"Error al autenticar: {ex.Message}");

            return (false, errorMsg, null);
        }
    }

    public async Task<bool> SignInAsync(string email, string password)
    {
        var (exito, _, _) = await IniciarSesionAsync(email, password);
        return exito;
    }

    public async Task<bool> SignUpAsync(string email, string password, string nombreCompleto)
    {
        try
        {
            var options = new Supabase.Gotrue.SignUpOptions
            {
                Data = new Dictionary<string, object>
                {
                    { "full_name", nombreCompleto },
                    { "nombre", nombreCompleto }
                }
            };
            var session = await Client.Auth.SignUp(email, password, options);
            if (session != null && session.User != null)
            {
                if (!string.IsNullOrEmpty(session.AccessToken) && !string.IsNullOrEmpty(session.RefreshToken))
                {
                    await GuardarSesionStorageAsync(session.AccessToken, session.RefreshToken);
                }

                OnAuthStateChange?.Invoke();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error de registro: {ex.Message}");
            return false;
        }
    }

    public async Task SignOutAsync()
    {
        try
        {
            await Client.Auth.SignOut();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error al cerrar sesión: {ex.Message}");
        }
        finally
        {
            await BorrarSesionStorageAsync();
            OnAuthStateChange?.Invoke();
        }
    }

    public async Task<PerfilModel?> GetPerfilUsuarioAsync()
    {
        try
        {
            var user = Client.Auth.CurrentUser;
            if (user == null || string.IsNullOrEmpty(user.Id)) return null;

            var response = await Client.From<PerfilModel>()
                .Where(p => p.Id == Guid.Parse(user.Id))
                .Single();

            return response;
        }
        catch
        {
            return null;
        }
    }

    public async Task<List<RoleModel>> GetRolesAsync()
    {
        try
        {
            var response = await Client.From<RoleModel>()
                .Order(r => r.Nombre, Supabase.Postgrest.Constants.Ordering.Ascending)
                .Get();
            return response.Models;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error obteniendo roles: {ex.Message}");
            return new List<RoleModel>();
        }
    }

    public async Task<List<PerfilModel>> GetPerfilesAsync()
    {
        try
        {
            var roles = await GetRolesAsync();
            var response = await Client.From<PerfilModel>()
                .Order(p => p.CreadoEn, Supabase.Postgrest.Constants.Ordering.Descending)
                .Get();

            var perfiles = response.Models;
            foreach (var p in perfiles)
            {
                p.Rol = roles.FirstOrDefault(r => r.Id.Equals(p.RolId, StringComparison.OrdinalIgnoreCase));
            }
            return perfiles;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error obteniendo perfiles: {ex.Message}");
            return new List<PerfilModel>();
        }
    }

    public async Task<(bool Exito, string? Mensaje)> AdminCrearUsuarioAsync(string email, string password, string nombre, string rol, string? telefono)
    {
        try
        {
            var parameters = new Dictionary<string, object>
            {
                { "p_email", email.Trim().ToLowerInvariant() },
                { "p_password", password },
                { "p_nombre", nombre.Trim() },
                { "p_rol", rol },
                { "p_telefono", telefono?.Trim() ?? string.Empty }
            };

            await Client.Rpc("admin_crear_usuario", parameters);
            return (true, null);
        }
        catch (Exception rpcEx)
        {
            Console.WriteLine($"RPC admin_crear_usuario: {rpcEx.Message}. Intentando registro Gotrue...");
            try
            {
                var options = new Supabase.Gotrue.SignUpOptions
                {
                    Data = new Dictionary<string, object>
                    {
                        { "full_name", nombre.Trim() },
                        { "nombre", nombre.Trim() },
                        { "rol", rol },
                        { "telefono", telefono?.Trim() ?? string.Empty }
                    }
                };
                var session = await Client.Auth.SignUp(email.Trim().ToLowerInvariant(), password, options);
                if (session?.User != null)
                {
                    return (true, null);
                }
                return (false, "No se pudo registrar el usuario en Supabase.");
            }
            catch (Exception ex)
            {
                return (false, ex.Message);
            }
        }
    }

    public async Task<bool> AdminActualizarPerfilAsync(Guid usuarioId, string nombreCompleto, string rolId, string? telefono, bool activo)
    {
        try
        {
            var parameters = new Dictionary<string, object>
            {
                { "p_usuario_id", usuarioId },
                { "p_nombre_completo", nombreCompleto.Trim() },
                { "p_rol_id", rolId },
                { "p_telefono", telefono?.Trim() ?? string.Empty },
                { "p_activo", activo }
            };

            await Client.Rpc("admin_actualizar_perfil", parameters);
            return true;
        }
        catch (Exception rpcEx)
        {
            Console.WriteLine($"RPC admin_actualizar_perfil: {rpcEx.Message}. Actualizando PostgREST directo...");
            try
            {
                await Client.From<PerfilModel>()
                    .Where(p => p.Id == usuarioId)
                    .Set(p => p.NombreCompleto, nombreCompleto.Trim())
                    .Set(p => p.RolId, rolId)
                    .Set(p => p.Telefono, telefono?.Trim())
                    .Set(p => p.Activo, activo)
                    .Set(p => p.ActualizadoEn, DateTime.UtcNow)
                    .Update();
                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error actualizando perfil: {ex.Message}");
                return false;
            }
        }
    }

    public async Task<bool> AdminAlternarActivoUsuarioAsync(Guid usuarioId, bool activo)
    {
        try
        {
            var parameters = new Dictionary<string, object>
            {
                { "p_usuario_id", usuarioId },
                { "p_activo", activo }
            };

            await Client.Rpc("admin_alternar_activo", parameters);
            return true;
        }
        catch
        {
            try
            {
                await Client.From<PerfilModel>()
                    .Where(p => p.Id == usuarioId)
                    .Set(p => p.Activo, activo)
                    .Set(p => p.ActualizadoEn, DateTime.UtcNow)
                    .Update();
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    public async Task<(bool Exito, string? Mensaje)> AdminCambiarPasswordAsync(Guid usuarioId, string nuevaPassword)
    {
        try
        {
            var parameters = new Dictionary<string, object>
            {
                { "p_usuario_id", usuarioId },
                { "p_nueva_password", nuevaPassword }
            };

            await Client.Rpc("admin_cambiar_password", parameters);
            return (true, null);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cambiando contraseña: {ex.Message}");
            return (false, ex.Message);
        }
    }

    // =========================================================================
    // MESAS, TARIFAS Y SESIONES
    // =========================================================================
    public async Task<List<MesaModel>> GetMesasAsync(bool soloActivas = true)
    {
        try
        {
            // Chequeo automático de expiración de reservas en cada consulta
            _ = VerificarYExpirarReservasAsync();

            var query = Client.From<MesaModel>()
                .Order(m => m.Numero, Supabase.Postgrest.Constants.Ordering.Ascending);

            if (soloActivas)
            {
                query = query.Where(m => m.Activa == true);
            }

            var response = await query.Get();
            var mesas = response.Models;

            // Enlazar tarifas, sesiones activas y reservas activas
            var tarifas = await GetTarifasAsync(false);
            var sesionesActivas = await GetSesionesActivasAsync();
            var reservasActivas = await GetReservasActivasAsync();

            foreach (var mesa in mesas)
            {
                if (mesa.TarifaDefectoId.HasValue)
                {
                    mesa.Tarifa = tarifas.FirstOrDefault(t => t.Id == mesa.TarifaDefectoId.Value);
                }
                mesa.Tarifa ??= tarifas.FirstOrDefault();

                mesa.SesionActiva = sesionesActivas.FirstOrDefault(s => s.MesaId == mesa.Id);
                if (mesa.SesionActiva != null)
                {
                    // Calcular tiempo y monto
                    CalcularTiempoYMontoMesa(mesa);
                }

                mesa.ReservaActiva = reservasActivas.FirstOrDefault(r => r.MesaId == mesa.Id);
            }

            return mesas;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error obteniendo mesas: {ex.Message}");
            return new List<MesaModel>();
        }
    }

    public void CalcularTiempoYMontoMesa(MesaModel mesa)
    {
        if (mesa.SesionActiva == null) return;

        // Convertir ambas marcas de tiempo explícitamente a UTC para evitar desfases con la zona horaria local (ej. UTC-4)
        var ahoraUtc = (mesa.SesionActiva.HoraFin?.ToUniversalTime()) ?? DateTime.UtcNow;
        var inicioUtc = mesa.SesionActiva.HoraInicio.ToUniversalTime();
        var segundosBrutos = (int)Math.Max(0, (ahoraUtc - inicioUtc).TotalSeconds);

        var segundosPausaActual = 0;
        if (mesa.SesionActiva.Estado == "pausada" && mesa.SesionActiva.PausaActivaInicio.HasValue)
        {
            var pausaInicioUtc = mesa.SesionActiva.PausaActivaInicio.Value.ToUniversalTime();
            segundosPausaActual = (int)Math.Max(0, (ahoraUtc - pausaInicioUtc).TotalSeconds);
        }

        var segundosNetos = Math.Max(0, segundosBrutos - (mesa.SesionActiva.SegundosPausados + segundosPausaActual));

        var ts = TimeSpan.FromSeconds(segundosNetos);
        mesa.TiempoTranscurridoStr = $"{(int)ts.TotalHours:D2}:{ts.Minutes:D2}:{ts.Seconds:D2}";

        var minutosTranscurridos = (int)Math.Ceiling(segundosNetos / 60.0);
        var tarifa = mesa.Tarifa;
        if (tarifa != null)
        {
            int minutosCobrables;
            if (minutosTranscurridos <= tarifa.MinutosTolerancia)
            {
                minutosCobrables = 0;
            }
            else if (minutosTranscurridos < tarifa.MinutosMinimo)
            {
                minutosCobrables = tarifa.MinutosMinimo;
            }
            else
            {
                minutosCobrables = minutosTranscurridos;
            }

            mesa.MontoTiempoCalculado = Math.Round(minutosCobrables * (tarifa.PrecioPorHora / 60m), 2);
        }
    }

    public async Task<List<TarifaModel>> GetTarifasAsync(bool soloActivas = true)
    {
        try
        {
            var query = Client.From<TarifaModel>()
                .Order(t => t.PrecioPorHora, Supabase.Postgrest.Constants.Ordering.Ascending);

            if (soloActivas)
            {
                query = query.Where(t => t.Activo == true);
            }

            var response = await query.Get();
            return response.Models;
        }
        catch
        {
            return new List<TarifaModel>();
        }
    }

    public async Task<List<SesionBillarModel>> GetSesionesActivasAsync()
    {
        try
        {
            var response = await Client.From<SesionBillarModel>()
                .Filter(s => s.Estado, Supabase.Postgrest.Constants.Operator.In, new List<string> { "activa", "pausada", "pendiente_pago" })
                .Get();

            var sesiones = response.Models;

            // Si hay sesiones pausadas, asociar la hora de inicio de la pausa para congelar el cronómetro
            var pausadas = sesiones.Where(s => s.Estado == "pausada").ToList();
            if (pausadas.Any())
            {
                try
                {
                    var pausas = await Client.From<PausaSesionModel>()
                        .Filter(p => p.HoraFin, Supabase.Postgrest.Constants.Operator.Is, "null")
                        .Get();

                    foreach (var s in pausadas)
                    {
                        var p = pausas.Models.OrderByDescending(x => x.HoraInicio).FirstOrDefault(x => x.SesionId == s.Id);
                        if (p != null)
                        {
                            s.PausaActivaInicio = p.HoraInicio;
                        }
                    }
                }
                catch
                {
                    // Evitar que un error en pausas interrumpa la carga de sesiones
                }
            }

            return sesiones;
        }
        catch
        {
            return new List<SesionBillarModel>();
        }
    }

    public async Task<List<ConsumoMesaModel>> GetConsumosMesaAsync(Guid sesionId)
    {
        try
        {
            var response = await Client.From<ConsumoMesaModel>()
                .Where(c => c.SesionId == sesionId)
                .Order(c => c.CreadoEn, Supabase.Postgrest.Constants.Ordering.Ascending)
                .Get();

            var consumos = response.Models;
            var productos = await GetProductosAsync();

            foreach (var c in consumos)
            {
                c.Producto = productos.FirstOrDefault(p => p.Id == c.ProductoId);
            }

            return consumos;
        }
        catch
        {
            return new List<ConsumoMesaModel>();
        }
    }

    // =========================================================================
    // OPERACIONES RPC (CRÍTICAS / TRANSACCIONALES)
    // =========================================================================
    public async Task<bool> IniciarSesionMesaAsync(Guid mesaId, Guid? tarifaId, string clienteNombre)
    {
        try
        {
            // Si la mesa estaba en estado 'reservada', prepararla para el inicio
            try
            {
                var m = await Client.From<MesaModel>().Where(x => x.Id == mesaId).Single();
                if (m != null && m.Estado == "reservada")
                {
                    m.Estado = "disponible";
                    await Client.From<MesaModel>().Update(m);
                }
            }
            catch { }

            var userId = Client.Auth.CurrentUser?.Id;
            var parameters = new Dictionary<string, object?>
            {
                { "p_mesa_id", mesaId.ToString() },
                { "p_tarifa_id", tarifaId?.ToString() },
                { "p_cliente_nombre", string.IsNullOrWhiteSpace(clienteNombre) ? "Cliente Mostrador" : clienteNombre },
                { "p_usuario_id", userId }
            };

            var res = await Client.Rpc("iniciar_sesion_mesa", parameters);

            // Completar cualquier reserva activa que tuviera esta mesa
            try
            {
                var reservas = await Client.From<ReservaMesaModel>()
                    .Where(r => r.MesaId == mesaId && r.Estado == "activa")
                    .Get();
                foreach (var r in reservas.Models)
                {
                    r.Estado = "completada";
                    await Client.From<ReservaMesaModel>().Update(r);
                }
            }
            catch { }

            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error iniciando sesión: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> PausarSesionMesaAsync(Guid sesionId, string motivo = "Pausa solicitada")
    {
        try
        {
            var parameters = new Dictionary<string, object?>
            {
                { "p_sesion_id", sesionId.ToString() },
                { "p_motivo", motivo }
            };

            await Client.Rpc("pausar_sesion_mesa", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error pausando sesión: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> ReanudarSesionMesaAsync(Guid sesionId)
    {
        try
        {
            var parameters = new Dictionary<string, object?>
            {
                { "p_sesion_id", sesionId.ToString() }
            };

            await Client.Rpc("reanudar_sesion_mesa", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error reanudando sesión: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> CambiarMesaAsync(Guid sesionId, Guid nuevaMesaId, string motivo = "Cambio solicitado")
    {
        try
        {
            var parameters = new Dictionary<string, object?>
            {
                { "p_sesion_id", sesionId.ToString() },
                { "p_nueva_mesa_id", nuevaMesaId.ToString() },
                { "p_motivo", motivo }
            };

            await Client.Rpc("cambiar_mesa_sesion", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cambiando de mesa: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> AgregarConsumoMesaAsync(Guid sesionId, Guid productoId, int cantidad)
    {
        try
        {
            var userId = Client.Auth.CurrentUser?.Id;
            var parameters = new Dictionary<string, object?>
            {
                { "p_sesion_id", sesionId.ToString() },
                { "p_producto_id", productoId.ToString() },
                { "p_cantidad", cantidad },
                { "p_usuario_id", userId }
            };

            await Client.Rpc("agregar_consumo_mesa", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error agregando consumo: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> AnularConsumoMesaAsync(Guid consumoId, string motivo)
    {
        try
        {
            var userId = Client.Auth.CurrentUser?.Id;
            var parameters = new Dictionary<string, object?>
            {
                { "p_consumo_id", consumoId.ToString() },
                { "p_motivo", motivo },
                { "p_usuario_id", userId }
            };

            await Client.Rpc("anular_consumo_mesa", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error anulando consumo: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> FinalizarSesionMesaAsync(Guid sesionId)
    {
        try
        {
            var userId = Client.Auth.CurrentUser?.Id;
            var parameters = new Dictionary<string, object?>
            {
                { "p_sesion_id", sesionId.ToString() },
                { "p_usuario_id", userId }
            };

            await Client.Rpc("finalizar_sesion_mesa", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error finalizando tiempo: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> LiquidarSesionMesaAsync(Guid sesionId, Guid cajaId, string metodoPago, decimal? montoRecibido, decimal descuento, string? referencia)
    {
        try
        {
            var userIdStr = Client.Auth.CurrentUser?.Id;
            Guid? userGuid = Guid.TryParse(userIdStr, out var uG) ? uG : null;

            var parameters = new Dictionary<string, object?>
            {
                { "p_sesion_id", sesionId.ToString() },
                { "p_caja_id", cajaId.ToString() },
                { "p_metodo_pago", metodoPago },
                { "p_monto_recibido", montoRecibido },
                { "p_descuento", descuento },
                { "p_referencia_comprobante", referencia },
                { "p_usuario_id", userGuid }
            };

            await Client.Rpc("liquidar_sesion_mesa", parameters);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error liquidando cuenta: {ex.Message}");
            return false;
        }
    }

    public async Task<(bool Exito, string? Mensaje)> VentaDirectaPosAsync(Guid cajaId, string clienteNombre, List<object> items, string metodoPago, decimal? montoRecibido, decimal descuento, string? referencia)
    {
        try
        {
            var userIdStr = Client.Auth.CurrentUser?.Id;
            Guid? userGuid = Guid.TryParse(userIdStr, out var uG) ? uG : null;

            var parameters = new Dictionary<string, object?>
            {
                { "p_caja_id", cajaId.ToString() },
                { "p_cliente_nombre", clienteNombre },
                { "p_items", items },
                { "p_metodo_pago", metodoPago.ToLowerInvariant() },
                { "p_monto_recibido", montoRecibido },
                { "p_descuento", descuento },
                { "p_referencia_comprobante", referencia },
                { "p_usuario_id", userGuid }
            };

            await Client.Rpc("venta_directa_pos", parameters);
            return (true, null);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error en venta directa: {ex.Message}");
            return (false, ex.Message);
        }
    }

    // =========================================================================
    // PRODUCTOS Y CATEGORIAS
    // =========================================================================
    public async Task<List<ProductoModel>> GetProductosAsync()
    {
        try
        {
            var response = await Client.From<ProductoModel>()
                .Order(p => p.Nombre, Supabase.Postgrest.Constants.Ordering.Ascending)
                .Get();
            return response.Models;
        }
        catch
        {
            return new List<ProductoModel>();
        }
    }

    public async Task<List<CategoriaModel>> GetCategoriasAsync()
    {
        try
        {
            var response = await Client.From<CategoriaModel>()
                .Order(c => c.Orden, Supabase.Postgrest.Constants.Ordering.Ascending)
                .Get();
            return response.Models;
        }
        catch
        {
            return new List<CategoriaModel>();
        }
    }

    public async Task<bool> GuardarCategoriaAsync(CategoriaModel categoria)
    {
        try
        {
            if (categoria.Id == Guid.Empty)
            {
                categoria.Id = Guid.NewGuid();
                categoria.CreadoEn = DateTime.UtcNow;
                await Client.From<CategoriaModel>().Insert(categoria);
            }
            else
            {
                await Client.From<CategoriaModel>().Update(categoria);
            }
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando categoría: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> EliminarCategoriaAsync(Guid categoriaId)
    {
        try
        {
            await Client.From<CategoriaModel>()
                .Where(c => c.Id == categoriaId)
                .Delete();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error eliminando categoría: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> GuardarProductoAsync(ProductoModel producto)
    {
        try
        {
            var esNuevo = producto.Id == Guid.Empty;
            if (esNuevo)
            {
                producto.Id = Guid.NewGuid();
                producto.CreadoEn = DateTime.UtcNow;
                producto.ActualizadoEn = DateTime.UtcNow;

                await Client.From<ProductoModel>().Insert(producto);

                if (producto.Stock > 0)
                {
                    await Client.From<MovimientoInventarioModel>().Insert(new MovimientoInventarioModel
                    {
                        Id = Guid.NewGuid(),
                        ProductoId = producto.Id,
                        Tipo = "entrada",
                        Cantidad = producto.Stock,
                        StockAnterior = 0,
                        StockNuevo = producto.Stock,
                        Motivo = "Inventario inicial al registrar producto",
                        CreadoEn = DateTime.UtcNow
                    });
                }
            }
            else
            {
                producto.ActualizadoEn = DateTime.UtcNow;
                await Client.From<ProductoModel>().Update(producto);
            }
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando producto: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> RegistrarEntradaStockAsync(Guid productoId, int cantidad, string motivo)
    {
        try
        {
            if (cantidad <= 0) return false;

            var response = await Client.From<ProductoModel>().Where(p => p.Id == productoId).Single();
            if (response == null) return false;

            var stockAnterior = response.Stock;
            var stockNuevo = stockAnterior + cantidad;
            response.Stock = stockNuevo;
            response.ActualizadoEn = DateTime.UtcNow;

            await Client.From<ProductoModel>().Update(response);

            await Client.From<MovimientoInventarioModel>().Insert(new MovimientoInventarioModel
            {
                Id = Guid.NewGuid(),
                ProductoId = productoId,
                Tipo = "entrada",
                Cantidad = cantidad,
                StockAnterior = stockAnterior,
                StockNuevo = stockNuevo,
                Motivo = string.IsNullOrWhiteSpace(motivo) ? "Entrada de mercadería / reposición" : motivo,
                CreadoEn = DateTime.UtcNow
            });

            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error ingresando stock: {ex.Message}");
            return false;
        }
    }

    // =========================================================================
    // CAJA
    // =========================================================================
    public async Task<CajaModel?> GetCajaAbiertaAsync()
    {
        try
        {
            var response = await Client.From<CajaModel>()
                .Where(c => c.Estado == "abierta")
                .Order(c => c.HoraApertura, Supabase.Postgrest.Constants.Ordering.Descending)
                .Limit(1)
                .Get();

            return response.Models.FirstOrDefault();
        }
        catch
        {
            return null;
        }
    }

    public async Task<bool> AbrirCajaAsync(string nombre, decimal montoInicial)
    {
        try
        {
            var userId = Client.Auth.CurrentUser?.Id;
            var parameters = new Dictionary<string, object?>
            {
                { "p_nombre", nombre },
                { "p_monto_inicial", montoInicial },
                { "p_usuario_id", userId }
            };

            await Client.Rpc("abrir_caja", parameters);
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error abriendo caja: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> CerrarCajaAsync(Guid cajaId, decimal montoReal, string? observaciones)
    {
        try
        {
            var userId = Client.Auth.CurrentUser?.Id;
            var parameters = new Dictionary<string, object?>
            {
                { "p_caja_id", cajaId.ToString() },
                { "p_monto_real_efectivo", montoReal },
                { "p_observaciones", observaciones },
                { "p_usuario_id", userId }
            };

            await Client.Rpc("cerrar_caja", parameters);
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cerrando caja: {ex.Message}");
            return false;
        }
    }

    // =========================================================================
    // ADMINISTRACIÓN DE MESAS, TARIFAS Y RESERVAS (CONFIGURACIÓN)
    // =========================================================================
    public async Task<bool> GuardarMesaAsync(MesaModel mesa)
    {
        try
        {
            if (mesa.Id == Guid.Empty)
            {
                mesa.Id = Guid.NewGuid();
                mesa.CreadoEn = DateTime.UtcNow;
                mesa.ActualizadoEn = DateTime.UtcNow;
                await Client.From<MesaModel>().Insert(mesa);
            }
            else
            {
                mesa.ActualizadoEn = DateTime.UtcNow;
                await Client.From<MesaModel>().Update(mesa);
            }
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando mesa: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> CambiarEstadoMesaAsync(Guid mesaId, string nuevoEstado)
    {
        try
        {
            var mesa = await Client.From<MesaModel>().Where(m => m.Id == mesaId).Single();
            if (mesa == null) return false;

            mesa.Estado = nuevoEstado;
            mesa.ActualizadoEn = DateTime.UtcNow;
            await Client.From<MesaModel>().Update(mesa);

            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cambiando estado mesa: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> DarDeBajaMesaAsync(Guid mesaId, bool activa)
    {
        try
        {
            var mesa = await Client.From<MesaModel>().Where(m => m.Id == mesaId).Single();
            if (mesa == null) return false;

            mesa.Activa = activa;
            mesa.ActualizadoEn = DateTime.UtcNow;
            await Client.From<MesaModel>().Update(mesa);

            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error alternando estado de activación de mesa: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> EliminarMesaAsync(Guid mesaId)
    {
        try
        {
            await Client.From<MesaModel>().Where(m => m.Id == mesaId).Delete();
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error eliminando mesa: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> GuardarTarifaAsync(TarifaModel tarifa)
    {
        try
        {
            if (tarifa.Id == Guid.Empty)
            {
                tarifa.Id = Guid.NewGuid();
                tarifa.CreadoEn = DateTime.UtcNow;
                tarifa.ActualizadoEn = DateTime.UtcNow;
                await Client.From<TarifaModel>().Insert(tarifa);
            }
            else
            {
                tarifa.ActualizadoEn = DateTime.UtcNow;
                await Client.From<TarifaModel>().Update(tarifa);
            }
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando tarifa: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> EliminarTarifaAsync(Guid tarifaId)
    {
        try
        {
            await Client.From<TarifaModel>().Where(t => t.Id == tarifaId).Delete();
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error eliminando tarifa: {ex.Message}");
            return false;
        }
    }

    public async Task<List<ReservaMesaModel>> GetReservasAsync(string? estado = null)
    {
        try
        {
            var query = Client.From<ReservaMesaModel>()
                .Order(r => r.Fecha, Supabase.Postgrest.Constants.Ordering.Descending)
                .Order(r => r.HoraInicio, Supabase.Postgrest.Constants.Ordering.Descending);

            if (!string.IsNullOrWhiteSpace(estado) && estado != "todos")
            {
                query = query.Where(r => r.Estado == estado);
            }

            var response = await query.Get();
            var reservas = response.Models;

            var mesas = await Client.From<MesaModel>().Get();
            foreach (var r in reservas)
            {
                r.Mesa = mesas.Models.FirstOrDefault(m => m.Id == r.MesaId);
            }

            return reservas;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error obteniendo reservas: {ex.Message}");
            return new List<ReservaMesaModel>();
        }
    }

    public async Task<List<ReservaMesaModel>> GetReservasActivasAsync()
    {
        try
        {
            var response = await Client.From<ReservaMesaModel>()
                .Where(r => r.Estado == "activa")
                .Get();
            return response.Models;
        }
        catch
        {
            return new List<ReservaMesaModel>();
        }
    }

    public async Task<bool> CrearReservaMesaAsync(Guid mesaId, string clienteNombre, string? telefono, DateTime fecha, TimeSpan horaInicio, TimeSpan horaFin, int toleranciaMinutos = 15, string? notas = null)
    {
        var dtInicioLocal = new DateTime(fecha.Year, fecha.Month, fecha.Day, horaInicio.Hours, horaInicio.Minutes, 0, DateTimeKind.Local);
        var dtFinLocal = new DateTime(fecha.Year, fecha.Month, fecha.Day, horaFin.Hours, horaFin.Minutes, 0, DateTimeKind.Local);

        var inicioUtc = dtInicioLocal.ToUniversalTime();
        var finUtc = dtFinLocal.ToUniversalTime();

        // 1. Intentar llamar al procedimiento almacenado RPC de Supabase (atómico)
        try
        {
            var rpcParams = new Dictionary<string, object?>
            {
                { "p_mesa_id", mesaId.ToString() },
                { "p_cliente_nombre", clienteNombre.Trim() },
                { "p_telefono", telefono?.Trim() },
                { "p_fecha", fecha.ToString("yyyy-MM-dd") },
                { "p_hora_inicio", horaInicio.ToString(@"hh\:mm\:ss") },
                { "p_hora_fin", horaFin.ToString(@"hh\:mm\:ss") },
                { "p_inicio_utc", inicioUtc.ToString("o") },
                { "p_fin_utc", finUtc.ToString("o") },
                { "p_tolerancia_minutos", toleranciaMinutos },
                { "p_notas", notas?.Trim() }
            };

            await Client.Rpc("crear_reserva_mesa", rpcParams);
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception rpcEx)
        {
            Console.WriteLine($"RPC crear_reserva_mesa: {rpcEx.Message}. Intentando inserción directa...");
        }

        // 2. Fallback: inserción directa en tabla reservas_mesa
        try
        {
            var reserva = new ReservaMesaModel
            {
                Id = Guid.NewGuid(),
                MesaId = mesaId,
                ClienteNombre = clienteNombre.Trim(),
                Telefono = telefono?.Trim(),
                Fecha = fecha.Date,
                HoraInicio = horaInicio.ToString(@"hh\:mm"),
                HoraFin = horaFin.ToString(@"hh\:mm"),
                InicioUtc = inicioUtc,
                FinUtc = finUtc,
                MinutosToleranciaLlegada = toleranciaMinutos,
                Estado = "activa",
                Notas = notas?.Trim(),
                CreadoEn = DateTime.UtcNow
            };

            await Client.From<ReservaMesaModel>().Insert(reserva);

            // Actualizar mesa a reservada
            var mesa = await Client.From<MesaModel>().Where(m => m.Id == mesaId).Single();
            if (mesa != null && mesa.Estado == "disponible")
            {
                mesa.Estado = "reservada";
                mesa.ActualizadoEn = DateTime.UtcNow;
                await Client.From<MesaModel>().Update(mesa);
            }

            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error registrando reserva: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> CancelarReservaMesaAsync(Guid reservaId)
    {
        // 1. Intentar RPC
        try
        {
            await Client.Rpc("cancelar_reserva_mesa", new Dictionary<string, object?>
            {
                { "p_reserva_id", reservaId.ToString() },
                { "p_motivo", "Cancelada por el operador" }
            });
            OnMesasUpdated?.Invoke();
            return true;
        }
        catch { }

        // 2. Fallback directo
        try
        {
            var reserva = await Client.From<ReservaMesaModel>().Where(r => r.Id == reservaId).Single();
            if (reserva == null) return false;

            reserva.Estado = "cancelada";
            await Client.From<ReservaMesaModel>().Update(reserva);

            var mesa = await Client.From<MesaModel>().Where(m => m.Id == reserva.MesaId).Single();
            if (mesa != null && mesa.Estado == "reservada")
            {
                mesa.Estado = "disponible";
                mesa.ActualizadoEn = DateTime.UtcNow;
                await Client.From<MesaModel>().Update(mesa);
            }

            OnMesasUpdated?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cancelando reserva: {ex.Message}");
            return false;
        }
    }

    public async Task<int> VerificarYExpirarReservasAsync()
    {
        // 1. Intentar RPC
        try
        {
            var rpcRes = await Client.Rpc("verificar_y_liberar_reservas_expiradas", new Dictionary<string, object?>());
            if (rpcRes != null && int.TryParse(rpcRes.Content, out int count) && count > 0)
            {
                OnMesasUpdated?.Invoke();
                return count;
            }
        }
        catch { }

        // 2. Fallback en C#
        try
        {
            var ahoraUtc = DateTime.UtcNow;
            var response = await Client.From<ReservaMesaModel>()
                .Where(r => r.Estado == "activa")
                .Get();

            var expiradas = 0;
            foreach (var r in response.Models)
            {
                var toleranciaUtc = r.InicioUtc.AddMinutes(r.MinutosToleranciaLlegada);
                // Si la hora de fin ya pasó O si ya pasaron los minutos de tolerancia tras la hora de inicio
                if (ahoraUtc > r.FinUtc || ahoraUtc > toleranciaUtc)
                {
                    r.Estado = "expirada";
                    await Client.From<ReservaMesaModel>().Update(r);

                    var mesa = await Client.From<MesaModel>().Where(m => m.Id == r.MesaId).Single();
                    if (mesa != null && mesa.Estado == "reservada")
                    {
                        mesa.Estado = "disponible";
                        mesa.ActualizadoEn = DateTime.UtcNow;
                        await Client.From<MesaModel>().Update(mesa);
                    }
                    expiradas++;
                }
            }

            if (expiradas > 0)
            {
                OnMesasUpdated?.Invoke();
            }

            return expiradas;
        }
        catch
        {
            return 0;
        }
    }

    // =========================================================================
    // MOVIMIENTOS Y AUDITORÍA DEL SISTEMA
    // =========================================================================
    public async Task<List<MovimientoSistemaModel>> GetMovimientosSistemaAsync(string? moduloFiltro = null, int limit = 200)
    {
        // 1. Intentar consultar directamente la vista unificada en Supabase
        try
        {
            var query = Client.From<MovimientoSistemaModel>()
                .Order(m => m.Fecha, Supabase.Postgrest.Constants.Ordering.Descending)
                .Limit(limit);

            if (!string.IsNullOrWhiteSpace(moduloFiltro) && moduloFiltro != "todos")
            {
                query = query.Where(m => m.Modulo == moduloFiltro);
            }

            var response = await query.Get();
            if (response.Models != null && response.Models.Any())
            {
                return response.Models;
            }
        }
        catch
        {
            // Si la vista aún no está desplegada en BD, ejecutar agregación en C#
        }

        // 2. Fallback: agregación resiliente en C# de todas las tablas operativas
        try
        {
            var lista = new List<MovimientoSistemaModel>();

            // A. Ventas
            if (string.IsNullOrWhiteSpace(moduloFiltro) || moduloFiltro == "todos" || moduloFiltro == "Ventas")
            {
                try
                {
                    var ventasRes = await Client.From<VentaModel>()
                        .Order(v => v.CreadoEn, Supabase.Postgrest.Constants.Ordering.Descending)
                        .Limit(50)
                        .Get();

                    foreach (var v in ventasRes.Models)
                    {
                        lista.Add(new MovimientoSistemaModel
                        {
                            Id = v.Id,
                            Modulo = "Ventas",
                            Tipo = v.TipoVenta,
                            Titulo = v.TipoVenta == "mesa" ? "Cobro de Mesa (Liquidación)" : "Venta Directa de Barra",
                            Detalle = $"Cliente: {v.ClienteNombre ?? "Cliente Mostrador"} | Total: Bs. {v.Total:N2} (Descuento: Bs. {v.Descuento:N2})",
                            Monto = v.Total,
                            Estado = v.Estado,
                            Usuario = v.UsuarioId,
                            Fecha = v.CreadoEn
                        });
                    }
                }
                catch { }
            }

            // B. Sesiones de billar (Mesas)
            if (string.IsNullOrWhiteSpace(moduloFiltro) || moduloFiltro == "todos" || moduloFiltro == "Mesas")
            {
                try
                {
                    var mesas = await Client.From<MesaModel>().Get();
                    var sesionesRes = await Client.From<SesionBillarModel>()
                        .Order(s => s.CreadoEn, Supabase.Postgrest.Constants.Ordering.Descending)
                        .Limit(50)
                        .Get();

                    foreach (var s in sesionesRes.Models)
                    {
                        var m = mesas.Models.FirstOrDefault(x => x.Id == s.MesaId);
                        var tituloEstado = s.Estado switch
                        {
                            "activa" => "En Juego",
                            "pausada" => "Pausada",
                            "pendiente_pago" => "Tiempo Concluido (Por Cobrar)",
                            "finalizada" => "Cobrada y Liberada",
                            _ => s.Estado
                        };

                        lista.Add(new MovimientoSistemaModel
                        {
                            Id = s.Id,
                            Modulo = "Mesas",
                            Tipo = s.Estado,
                            Titulo = $"Mesa {m?.Numero ?? 0} - {tituloEstado}",
                            Detalle = $"Cliente: {s.ClienteNombre ?? "Mostrador"} | Minutos: {s.MinutosCobrables} min | Total: Bs. {s.MontoTotal:N2}",
                            Monto = s.MontoTotal,
                            Estado = s.Estado,
                            Usuario = s.UsuarioInicioId,
                            Fecha = s.HoraFin ?? s.HoraInicio
                        });
                    }
                }
                catch { }
            }

            // C. Movimientos de Caja
            if (string.IsNullOrWhiteSpace(moduloFiltro) || moduloFiltro == "todos" || moduloFiltro == "Caja")
            {
                try
                {
                    var movCajaRes = await Client.From<MovimientoCajaModel>()
                        .Order(mc => mc.CreadoEn, Supabase.Postgrest.Constants.Ordering.Descending)
                        .Limit(50)
                        .Get();

                    foreach (var mc in movCajaRes.Models)
                    {
                        lista.Add(new MovimientoSistemaModel
                        {
                            Id = mc.Id,
                            Modulo = "Caja",
                            Tipo = mc.Tipo,
                            Titulo = $"Caja: {mc.Tipo.ToUpper()}",
                            Detalle = $"{mc.Descripcion} (Método: {mc.MetodoPago.ToUpper()})",
                            Monto = mc.Monto,
                            Estado = "completado",
                            Usuario = mc.UsuarioId,
                            Fecha = mc.CreadoEn
                        });
                    }
                }
                catch { }
            }

            // D. Movimientos de Inventario
            if (string.IsNullOrWhiteSpace(moduloFiltro) || moduloFiltro == "todos" || moduloFiltro == "Inventario")
            {
                try
                {
                    var productos = await GetProductosAsync();
                    var movInvRes = await Client.From<MovimientoInventarioModel>()
                        .Order(mi => mi.CreadoEn, Supabase.Postgrest.Constants.Ordering.Descending)
                        .Limit(50)
                        .Get();

                    foreach (var mi in movInvRes.Models)
                    {
                        var prod = productos.FirstOrDefault(p => p.Id == mi.ProductoId);
                        lista.Add(new MovimientoSistemaModel
                        {
                            Id = mi.Id,
                            Modulo = "Inventario",
                            Tipo = mi.Tipo,
                            Titulo = $"Inventario: {mi.Tipo}",
                            Detalle = $"{prod?.Nombre ?? "Artículo"} | Cant: {mi.Cantidad} (Stock: {mi.StockAnterior} → {mi.StockNuevo}) - {mi.Motivo}",
                            Monto = null,
                            Estado = "registrado",
                            Usuario = mi.UsuarioId,
                            Fecha = mi.CreadoEn
                        });
                    }
                }
                catch { }
            }

            return lista.OrderByDescending(m => m.Fecha).Take(limit).ToList();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error obteniendo movimientos: {ex.Message}");
            return new List<MovimientoSistemaModel>();
        }
    }
}
