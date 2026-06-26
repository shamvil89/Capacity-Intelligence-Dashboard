using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Middleware;
using DBA.Capacity.Api.Services;

Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddCors(options =>
{
    options.AddPolicy("LocalReactDevelopment", policy =>
    {
        policy
            .WithOrigins("http://localhost:5173", "http://127.0.0.1:5173")
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

builder.Services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();
builder.Services.AddScoped<ICapacityService, CapacityService>();
builder.Services.AddScoped<IDashboardService, DashboardService>();
builder.Services.AddScoped<IAlertService, AlertService>();
builder.Services.AddScoped<IServerService, ServerService>();

// TODO: Add Azure AD / Entra ID authentication.
// TODO: Add role-based access for DBA, reader, and operations roles.
// TODO: Use Managed Identity and Key Vault-backed secrets for deployed environments.

var app = builder.Build();

app.UseMiddleware<ErrorHandlingMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors("LocalReactDevelopment");
app.MapControllers();

app.Run();
