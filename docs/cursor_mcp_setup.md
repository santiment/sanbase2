# Setting up Sanbase MCP Server with Cursor IDE

This guide shows you how to configure your local Sanbase MCP server to work with Cursor IDE, enabling AI assistants to interact with your Sanbase project directly.

## Prerequisites

1. **Sanbase Phoenix Server Running**: Your Phoenix server must be running on `http://localhost:4000`
2. **Cursor IDE**: Make sure you have Cursor IDE installed
3. **Working MCP Server**: Verify your MCP server is responding (see testing section below)

## Step 1: Verify MCP Server is Working

Before configuring Cursor, test that your MCP server responds correctly:

```bash
# Test tools list
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' | jq .

# Test say_hi tool
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"say_hi","arguments":{"name":"Test","language":"en"}}}' | jq .
```

You should see successful responses with tool definitions and greetings.

## Step 2: Configure Cursor IDE

### Option A: User-level Configuration (Recommended)

1. **Open Cursor Settings**:
   - Press `Cmd+,` (macOS) or `Ctrl+,` (Windows/Linux)
   - Or go to: Cursor → Settings

2. **Navigate to MCP Settings**:
   - Search for "MCP" in the settings search bar
   - Or go to: Extensions → MCP

3. **Add MCP Server Configuration**:
   - Click "Edit in settings.json" or similar option
   - Add the following configuration:

```json
{
  "mcp.servers": {
    "sanbase": {
      "command": "http",
      "args": {
        "url": "http://localhost:4000/mcp",
        "method": "POST",
        "headers": {
          "Content-Type": "application/json"
        }
      }
    }
  }
}
```

### Option B: Workspace Configuration

Create a `.cursor/settings.json` file in your project root:

```json
{
  "mcp.servers": {
    "sanbase": {
      "command": "http",
      "args": {
        "url": "http://localhost:4000/mcp",
        "method": "POST",
        "headers": {
          "Content-Type": "application/json"
        }
      }
    }
  }
}
```

### Option C: MCP Configuration File

Create an MCP configuration file at `~/.config/mcp/settings.json`:

```json
{
  "servers": {
    "sanbase": {
      "command": "http-server",
      "args": {
        "url": "http://localhost:4000/mcp"
      }
    }
  }
}
```

## Step 3: Restart Cursor

After adding the configuration:

1. **Restart Cursor IDE** completely
2. **Reload the window** if needed: `Cmd+Shift+P` → "Developer: Reload Window"

## Step 4: Verify Connection

1. **Open Developer Tools** in Cursor:
   - `Cmd+Shift+P` → "Developer: Toggle Developer Tools"

2. **Check MCP Connection**:
   - Look for MCP-related logs in the console
   - You should see connection attempts to your local server

3. **Test in Chat**:
   - Open Cursor's AI chat
   - Try asking: "Can you use the say_hi tool to greet me?"
   - The AI should be able to call your MCP server

## Available Tools

Once configured, Cursor AI will have access to these Sanbase tools:

### `say_hi`
- **Description**: A friendly greeting tool
- **Parameters**:
  - `name` (string, optional): Name to greet (default: "World")
  - `language` (string, optional): Language for greeting (default: "en")
  - **Supported languages**: en, es, fr, de, bg

**Example usage in Cursor**:
> "Use the say_hi tool to greet me in French"

## Troubleshooting

### MCP Server Not Responding

1. **Check Phoenix Server**:
   ```bash
   curl http://localhost:4000/healthcheck
   ```

2. **Check MCP Route**:
   ```bash
   curl -X POST http://localhost:4000/mcp -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'
   ```

3. **Check Logs**:
   - Look at your Phoenix server logs for any errors
   - Check Cursor's developer console for connection errors

### Cursor Not Finding MCP Server

1. **Verify Configuration**:
   - Check that your JSON configuration is valid
   - Ensure the URL is exactly `http://localhost:4000/mcp`
   - Make sure there are no typos in the configuration

2. **Restart Everything**:
   - Restart your Phoenix server
   - Restart Cursor IDE
   - Try reloading the Cursor window

3. **Check Network**:
   - Ensure nothing is blocking localhost connections
   - Try accessing the URL directly in your browser

### Alternative Configuration for Different Cursor Versions

If the above doesn't work, try this alternative format:

```json
{
  "mcp": {
    "servers": [
      {
        "name": "sanbase",
        "url": "http://localhost:4000/mcp",
        "type": "http"
      }
    ]
  }
}
```

## Development Tips

### Adding New Tools

To add new tools to your MCP server:

1. **Define the tool** in `lib/sanbase/mcp/tools.ex`
2. **Add to the tools list** in the `list_tools/0` function
3. **Implement the execution** in the `call_tool/2` function
4. **Restart your Phoenix server**
5. **Restart Cursor** to pick up new tools

### Testing New Tools

Always test new tools with curl before testing in Cursor:

```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "tools/call",
    "params": {
      "name": "your_new_tool",
      "arguments": {
        "param1": "value1"
      }
    }
  }' | jq .
```

## Next Steps

Once your MCP server is connected to Cursor:

1. **Explore Integration**: Ask Cursor to use your Sanbase tools
2. **Add Domain-Specific Tools**: Create tools that expose Sanbase's core functionality
3. **Enhance Documentation**: Add more detailed tool descriptions for better AI understanding

## Security Notes

- **Local Development Only**: This setup is for local development
- **No Authentication**: The current setup has no authentication
- **Network Access**: Ensure your firewall allows localhost connections
- **Production Considerations**: For production, implement proper authentication and rate limiting

## Support

If you encounter issues:

1. **Check the logs**: Phoenix server logs and Cursor developer console
2. **Verify dependencies**: Ensure all required packages are installed
3. **Test manually**: Use curl to verify the MCP server works independently
4. **Review configuration**: Double-check JSON syntax and URLs 