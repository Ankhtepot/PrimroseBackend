using Microsoft.AspNetCore.Authorization;

namespace PrimroseBackend.Shared;

public static class Extensions
{
    public static RouteHandlerBuilder RequiredAdministrators(this RouteHandlerBuilder builder, string roles = "")
    {
        string finalRoles = string.IsNullOrWhiteSpace(roles) ? ProjectConstants.Roles.Admin : $"{ProjectConstants.Roles.Admin},{roles}";
        return builder.RequireAuthorization(new AuthorizeAttribute { Roles = finalRoles });
    }
}
