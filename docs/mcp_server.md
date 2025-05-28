# Sanbase MCP Server

The Sanbase project includes a built-in Model Context Protocol (MCP) server that exposes tools and capabilities to MCP-compatible clients.

## Overview

The MCP server follows the [Model Context Protocol specification](https://modelcontextprotocol.io/) version 2025-03-26 and provides a standardized way for AI applications to interact with Sanbase functionality.

## Architecture

The MCP implementation is organized into several modules following domain-driven design principles:

- `Sanbase.MCP` - Main context module providing the public API
- `Sanbase.MCP.Server` - Core protocol implementation handling JSON-RPC messages
- `Sanbase.MCP.Tools` - Tool definitions and implementations
- `SanbaseWeb.MCPController` - HTTP endpoint for MCP communication

## Available Tools

### say_hi

A friendly greeting tool that demonstrates basic MCP functionality.

**Parameters:**
- `name` (string, optional) - Name of the person to greet (default: "World")
- `language` (string, optional) - Language for the greeting (default: "en")
  - Supported languages: "en", "es", "fr", "de", "bg"

**Example usage:**
```json
{
  "name": "say_hi",
  "arguments": {
    "name": "Alice",
    "language": "fr"
  }
}
```

**Response:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "Bonjour, Alice! 👋"
    }
  ],
  "isError": false
}
```

## HTTP Endpoint

The MCP server is accessible via HTTP POST at `/mcp`. The endpoint accepts JSON-RPC 2.0 requests and supports both single requests and batch requests.

### Examples

#### Initialize Connection
```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": {
        "name": "example-client",
        "version": "1.0.0"
      }
    }
  }'
```

#### List Available Tools
```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "2",
    "method": "tools/list"
  }'
```

#### Call a Tool
```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "3",
    "method": "tools/call",
    "params": {
      "name": "say_hi",
      "arguments": {
        "name": "World",
        "language": "en"
      }
    }
  }'
```

#### Send Notification (No Response Expected)
```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "initialized"
  }'
```

## Supported Methods

- `initialize` - Initialize the MCP connection and negotiate capabilities
- `tools/list` - List all available tools with their schemas
- `tools/call` - Execute a specific tool with arguments
- `initialized` - Notification that client initialization is complete

## Server Capabilities

The current MCP server supports:

- **Tools**: Function calls that can be executed by MCP clients
- **List Change Notifications**: Server can notify clients when tool lists change

## Adding New Tools

To add a new tool to the MCP server:

1. **Define the tool schema** in `Sanbase.MCP.Tools`:
```elixir
defp my_new_tool_schema do
  %{
    "name" => "my_new_tool",
    "description" => "Description of what this tool does",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{
        "param1" => %{
          "type" => "string",
          "description" => "Description of param1"
        }
      }
    }
  }
end
```

2. **Add the schema to the tools list**:
```elixir
def list_tools do
  [
    say_hi_tool_schema(),
    my_new_tool_schema()  # Add your new tool here
  ]
end
```

3. **Implement the tool execution**:
```elixir
def call_tool("my_new_tool", arguments) do
  execute_my_new_tool(arguments)
end

defp execute_my_new_tool(arguments) do
  # Your tool implementation here
  result = %{
    "content" => [
      %{
        "type" => "text", 
        "text" => "Tool result"
      }
    ],
    "isError" => false
  }
  
  {:ok, result}
end
```

## Error Handling

The server follows JSON-RPC 2.0 error codes:

- `-32700` Parse error (invalid JSON)
- `-32600` Invalid Request
- `-32601` Method not found  
- `-32602` Invalid params
- `-32603` Internal error
- `-32000` Tool execution failed

## Testing

Run the MCP server tests:

```bash
mix test test/sanbase/mcp/
mix test test/sanbase_web/controllers/mcp_controller_test.exs
```

## MCP Client Compatibility

This server is compatible with MCP clients such as:

- Claude Desktop
- Cursor
- Windsurf
- Cline
- Any client implementing the Model Context Protocol specification

## Security Considerations

- The MCP server runs within the Phoenix application security context
- Tool execution is sandboxed within the Elixir application
- No external process execution or file system access by default
- All tool implementations should validate inputs appropriately
- Consider rate limiting for production deployments

## Future Extensions

The current implementation provides a foundation for:

- **Resources**: Exposing data sources and content to MCP clients
- **Prompts**: Pre-defined templates and workflows
- **Sampling**: Server-initiated LLM interactions
- **Authentication**: Secure access control for MCP operations 