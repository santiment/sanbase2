#!/bin/bash

# Test script for Sanbase MCP Server
# Run this script to verify your MCP server is working correctly

echo "🚀 Testing Sanbase MCP Server on localhost:4000..."
echo

# Test 1: Health check
echo "1. Testing Phoenix server health..."
curl -s http://localhost:4000/healthcheck > /dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ Phoenix server is responding"
else
    echo "   ❌ Phoenix server is not responding - make sure it's running with 'mix phx.server'"
    exit 1
fi
echo

# Test 2: Initialize MCP connection
echo "2. Testing MCP initialization..."
INIT_RESPONSE=$(curl -s -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -D /tmp/mcp_headers.txt \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": {
        "name": "test-client",
        "version": "1.0.0"
      }
    }
  }')

if echo "$INIT_RESPONSE" | jq -e '.result.serverInfo.name' > /dev/null 2>&1; then
    echo "   ✅ MCP initialization successful"
    echo "   📋 Server: $(echo "$INIT_RESPONSE" | jq -r '.result.serverInfo.name')"
    echo "   📋 Version: $(echo "$INIT_RESPONSE" | jq -r '.result.serverInfo.version')"
    
    # Extract session ID from headers
    SESSION_ID=$(grep -i "mcp-session-id:" /tmp/mcp_headers.txt | cut -d' ' -f2 | tr -d '\r\n')
    echo "   📋 Session ID: $SESSION_ID"
else
    echo "   ❌ MCP initialization failed"
    echo "   Response: $INIT_RESPONSE"
    exit 1
fi
echo

# Test 3: List available tools
echo "3. Testing tools/list..."
TOOLS_RESPONSE=$(curl -s -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":"2","method":"tools/list"}')

if echo "$TOOLS_RESPONSE" | jq -e '.result.tools[0].name' > /dev/null 2>&1; then
    echo "   ✅ Tools list retrieved successfully"
    TOOL_COUNT=$(echo "$TOOLS_RESPONSE" | jq '.result.tools | length')
    echo "   📋 Available tools: $TOOL_COUNT"
    echo "$TOOLS_RESPONSE" | jq -r '.result.tools[] | "      - \(.name): \(.description)"'
else
    echo "   ❌ Failed to retrieve tools list"
    echo "   Response: $TOOLS_RESPONSE"
    exit 1
fi
echo

# Test 4: Test say_hi tool
echo "4. Testing say_hi tool..."
SAY_HI_RESPONSE=$(curl -s -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": "3",
    "method": "tools/call",
    "params": {
      "name": "say_hi",
      "arguments": {
        "name": "Local Test",
        "language": "en"
      }
    }
  }')

if echo "$SAY_HI_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    echo "   ✅ say_hi tool executed successfully"
    GREETING=$(echo "$SAY_HI_RESPONSE" | jq -r '.result.content[0].text')
    echo "   📋 Response: $GREETING"
else
    echo "   ❌ say_hi tool execution failed"
    echo "   Response: $SAY_HI_RESPONSE"
    exit 1
fi
echo

# Test 5: Test different languages
echo "5. Testing say_hi tool with different languages..."
LANGUAGES=("es" "fr" "de" "bg")
LANG_NAMES=("Spanish" "French" "German" "Bulgarian")

for i in "${!LANGUAGES[@]}"; do
    LANG="${LANGUAGES[$i]}"
    LANG_NAME="${LANG_NAMES[$i]}"
    
    LANG_RESPONSE=$(curl -s -X POST http://localhost:4000/mcp \
      -H "Content-Type: application/json" \
      -H "mcp-session-id: $SESSION_ID" \
      -d "{
        \"jsonrpc\": \"2.0\",
        \"id\": \"$((4+i))\",
        \"method\": \"tools/call\",
        \"params\": {
          \"name\": \"say_hi\",
          \"arguments\": {
            \"name\": \"Test\",
            \"language\": \"$LANG\"
          }
        }
      }")
    
    if echo "$LANG_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
        GREETING=$(echo "$LANG_RESPONSE" | jq -r '.result.content[0].text')
        echo "   ✅ $LANG_NAME ($LANG): $GREETING"
    else
        echo "   ❌ $LANG_NAME ($LANG): Failed"
    fi
done
echo

# Test 6: Test list_available_metrics tool (summary format)
echo "6. Testing list_available_metrics tool (summary format)..."
METRICS_SUMMARY_RESPONSE=$(curl -s -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": "10",
    "method": "tools/call",
    "params": {
      "name": "list_available_metrics",
      "arguments": {
        "format": "summary"
      }
    }
  }')

if echo "$METRICS_SUMMARY_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    echo "   ✅ list_available_metrics (summary) executed successfully"
    SUMMARY_TEXT=$(echo "$METRICS_SUMMARY_RESPONSE" | jq -r '.result.content[0].text')
    TOTAL_METRICS=$(echo "$SUMMARY_TEXT" | grep "Total Metrics:" | head -1)
    echo "   📋 $TOTAL_METRICS"
else
    echo "   ❌ list_available_metrics (summary) execution failed"
    echo "   Response: $METRICS_SUMMARY_RESPONSE"
fi
echo

# Test 7: Test list_available_metrics tool (JSON format) - just verify it works, don't print the full JSON
echo "7. Testing list_available_metrics tool (JSON format)..."
METRICS_JSON_RESPONSE=$(curl -s -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": "11",
    "method": "tools/call",
    "params": {
      "name": "list_available_metrics",
      "arguments": {
        "format": "json"
      }
    }
  }')

if echo "$METRICS_JSON_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    echo "   ✅ list_available_metrics (JSON) executed successfully"
    JSON_TEXT=$(echo "$METRICS_JSON_RESPONSE" | jq -r '.result.content[0].text')
    if echo "$JSON_TEXT" | jq . > /dev/null 2>&1; then
        METRIC_COUNT=$(echo "$JSON_TEXT" | jq 'keys | length')
        echo "   📋 Returned $METRIC_COUNT metrics in JSON format"
    else
        echo "   ⚠️  Response is not valid JSON"
    fi
else
    echo "   ❌ list_available_metrics (JSON) execution failed"
    echo "   Response: $METRICS_JSON_RESPONSE"
fi
echo

echo "🎉 All MCP server tests completed successfully!"
echo
echo "Next steps:"
echo "1. Configure Cursor IDE using the guide in docs/cursor_mcp_setup.md"
echo "2. Add your own tools to lib/sanbase/mcp/tools.ex"
echo "3. Test new tools with this script"
echo 