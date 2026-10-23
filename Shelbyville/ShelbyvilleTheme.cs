using MudBlazor;

namespace Shelbyville;

public static class ShelbyvilleTheme
{
    public static MudTheme CreateTheme()
    {
        return new MudTheme
        {
            PaletteDark = new PaletteDark
            {
                Primary = "#164F3B",          // Verde billar
                Secondary = "#238B65",        // Verde esmeralda interactivo
                Tertiary = "#D4AF37",         // Dorado clásico de acento
                Background = "#0B1210",       // Negro verdoso
                Surface = "#1C2923",          // Verde oscuro
                DrawerBackground = "#101B16", // Verde negro
                DrawerText = "#F5F6F2",
                DrawerIcon = "#AAB8AE",
                AppbarBackground = "#101B16",
                AppbarText = "#F5F6F2",
                TextPrimary = "#F5F6F2",
                TextSecondary = "#AAB8AE",
                ActionDefault = "#D4AF37",
                ActionDisabled = "#6B7280",
                LinesDefault = "#34443C",
                TableLines = "#26372E",
                Success = "#22C55E",
                Warning = "#F59E0B",
                Error = "#EF4444",
                Info = "#38BDF8"
            },
            LayoutProperties = new LayoutProperties
            {
                DefaultBorderRadius = "12px",
                AppbarHeight = "64px"
            },
            Typography = new Typography
            {
                Default = new DefaultTypography
                {
                    FontFamily = new[] { "Inter", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif" }
                },
                H1 = new H1Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "700" },
                H2 = new H2Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "700" },
                H3 = new H3Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "600" },
                H4 = new H4Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "600" },
                H5 = new H5Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "600" },
                H6 = new H6Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "600" },
                Subtitle1 = new Subtitle1Typography { FontFamily = new[] { "Outfit", "sans-serif" }, FontWeight = "500" }
            }
        };
    }
}
