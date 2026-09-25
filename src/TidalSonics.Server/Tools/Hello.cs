using System.ComponentModel;
using ModelContextProtocol.Server;

namespace TidalSonics.Server.Tools;

[McpServerToolType]
public static class HelloTool
{
    [McpServerTool, Description("friendly greeting; hello world")]
    public static string Hello([Description("name to greet")] string name) 
        => $"hello, {name}. tidal sonics is uppin' runnin'";
}