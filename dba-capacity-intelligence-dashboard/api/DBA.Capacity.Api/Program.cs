using System.Security.Claims;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Middleware;
using DBA.Capacity.Api.Security;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();

var authEnabled = builder.Configuration.GetValue("Authentication:Enabled", false);
var adminRoles = GetConfiguredRoles(builder.Configuration, "Authorization:AdminRoles", ["DBA.Capacity.Admin"]);
var editorRoles = GetConfiguredRoles(builder.Configuration, "Authorization:EditorRoles", ["DBA.Capacity.Editor"]);
var readerRoles = GetConfiguredRoles(builder.Configuration, "Authorization:ReaderRoles", ["DBA.Capacity.Reader"]);

builder.Services.AddSwaggerGen(options =>
{
    if (!authEnabled)
    {
        return;
    }

    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Paste an Entra ID access token for the DBA Capacity API."
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            []
        }
    });
});

var allowedOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>()
    ?? ["http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:8080", "http://127.0.0.1:8080"];

builder.Services.AddCors(options =>
{
    options.AddPolicy("DashboardFrontend", policy =>
    {
        policy
            .WithOrigins(allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

builder.Services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();
builder.Services.AddSingleton<CollectorRunState>();
builder.Services.AddScoped<ICapacityService, CapacityService>();
builder.Services.AddScoped<IDashboardService, DashboardService>();
builder.Services.AddScoped<IAlertService, AlertService>();
builder.Services.AddScoped<IServerService, ServerService>();
builder.Services.AddScoped<ISettingsService, SettingsService>();
builder.Services.AddScoped<IApplicationCmdbService, ApplicationCmdbService>();
builder.Services.AddHttpClient<ICollectorRunService, AzureDevOpsCollectorRunService>();

if (authEnabled)
{
    var authority = builder.Configuration["Authentication:Authority"];
    var audience = builder.Configuration["Authentication:Audience"];

    if (string.IsNullOrWhiteSpace(authority))
    {
        throw new InvalidOperationException("Authentication is enabled, but Authentication:Authority is not configured.");
    }

    if (string.IsNullOrWhiteSpace(audience))
    {
        throw new InvalidOperationException("Authentication is enabled, but Authentication:Audience is not configured.");
    }

    builder.Services
        .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = authority;
            options.Audience = audience;
            options.RequireHttpsMetadata = builder.Configuration.GetValue("Authentication:RequireHttpsMetadata", true);
            options.TokenValidationParameters = new TokenValidationParameters
            {
                NameClaimType = "name",
                RoleClaimType = "roles",
                ValidateIssuer = true
            };
        });
}

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(AuthorizationPolicies.Reader, policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context => HasAnyConfiguredRole(context.User, adminRoles, editorRoles, readerRoles));
    });

    options.AddPolicy(AuthorizationPolicies.Editor, policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context => HasAnyConfiguredRole(context.User, adminRoles, editorRoles));
    });

    options.AddPolicy(AuthorizationPolicies.Admin, policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context => HasAnyConfiguredRole(context.User, adminRoles));
    });
});

// TODO: Use Managed Identity and Key Vault-backed secrets for deployed environments.

var app = builder.Build();

app.UseMiddleware<ErrorHandlingMiddleware>();

app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
app.UseCors("DashboardFrontend");

if (authEnabled)
{
    app.UseAuthentication();
    app.UseAuthorization();
}

app.MapGet("/", () => Results.Redirect("/swagger"));
app.MapGet("/health", () => Results.Ok(new
{
    status = "Healthy",
    service = "DBA Capacity API",
    timestampUtc = DateTimeOffset.UtcNow
}));
app.MapControllers();

app.Run();

static string[] GetConfiguredRoles(IConfiguration configuration, string key, string[] defaultRoles)
{
    var values = configuration
        .GetSection(key)
        .Get<string[]>()
        ?.Where(value => !string.IsNullOrWhiteSpace(value))
        .SelectMany(SplitRoleValues)
        .ToArray();

    if (values is { Length: > 0 })
    {
        return values;
    }

    var scalarValue = configuration[key];
    if (!string.IsNullOrWhiteSpace(scalarValue))
    {
        values = SplitRoleValues(scalarValue).ToArray();
        if (values.Length > 0)
        {
            return values;
        }
    }

    return defaultRoles;
}

static IEnumerable<string> SplitRoleValues(string value)
{
    return value
        .Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(role => !string.IsNullOrWhiteSpace(role));
}

static bool HasAnyConfiguredRole(ClaimsPrincipal user, params IEnumerable<string>[] roleSets)
{
    var allowedRoles = roleSets
        .SelectMany(roleSet => roleSet)
        .Where(role => !string.IsNullOrWhiteSpace(role))
        .ToHashSet(StringComparer.OrdinalIgnoreCase);

    if (allowedRoles.Count == 0)
    {
        return false;
    }

    return user.Claims
        .Where(claim => IsRoleLikeClaim(claim.Type))
        .SelectMany(claim => SplitRoleValues(claim.Value))
        .Any(allowedRoles.Contains);
}

static bool IsRoleLikeClaim(string claimType)
{
    return claimType.Equals(ClaimTypes.Role, StringComparison.OrdinalIgnoreCase)
        || claimType.Equals("roles", StringComparison.OrdinalIgnoreCase)
        || claimType.Equals("role", StringComparison.OrdinalIgnoreCase)
        || claimType.Equals("groups", StringComparison.OrdinalIgnoreCase)
        || claimType.Equals("wids", StringComparison.OrdinalIgnoreCase);
}
