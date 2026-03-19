defmodule Sanbase.MCP.Server do
  @moduledoc "MCP server for Sanbase metrics access"

  use Anubis.Server,
    name: "sanbase-metrics",
    version: "1.0.0",
    capabilities: [:tools, :prompts]

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    user = Sanbase.MCP.Auth.headers_list_to_user(frame.context.headers)
    frame = assign(frame, :current_user, user)
    {:ok, frame |> assign(:is_authenticated, not is_nil(user))}
  end

  @impl true
  def handle_request(%{"method" => "tools/call"} = request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)
    tool_name = get_in(request, ["params", "name"])
    params = get_in(request, ["params", "arguments"]) || %{}
    start_time = System.monotonic_time(:millisecond)

    result = Anubis.Server.Handlers.handle(request, __MODULE__, frame)

    duration_ms = System.monotonic_time(:millisecond) - start_time
    track_tool_invocation(result, frame, tool_name, params, duration_ms)

    result
  end

  def handle_request(request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)
    Anubis.Server.Handlers.handle(request, __MODULE__, frame)
  end

  # Register our metrics tools
  component(Sanbase.MCP.MetricsAndAssetsDiscoveryTool)
  component(Sanbase.MCP.FetchMetricDataTool)

  # Register our insights tools
  component(Sanbase.MCP.InsightDiscoveryTool)
  component(Sanbase.MCP.FetchInsightsTool)

  # Register our social data tools
  component(Sanbase.MCP.TrendingStoriesTool)
  component(Sanbase.MCP.CombinedTrendsTool)

  # Register Screener tool
  component(Sanbase.MCP.AssetsByMetricTool)

  # Register prompts
  component(Sanbase.MCP.Prompts.MarketAnalysis)
  component(Sanbase.MCP.Prompts.MarketPulseCheck)
  component(Sanbase.MCP.Prompts.MarketThesisValidation)

  if Application.compile_env(:sanbase, :env) in [:test, :dev] do
    IO.puts("Defining the extra MCP Server tools used in dev and test")
    # Some tools are enabled only in dev mode so we can test things during development
    component(Sanbase.MCP.CheckAuthentication)
  end

  defp track_tool_invocation(result, frame, tool_name, params, duration_ms) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      {is_successful, error_message, response_size_bytes} =
        case result do
          {:reply, %{"isError" => true, "content" => content}, _frame} ->
            error_msg =
              content
              |> Enum.map_join("\n", fn %{"text" => text} -> text end)

            size = response_size_bytes(content)
            {false, error_msg, size}

          {:reply, %{"content" => content}, _frame} ->
            size = response_size_bytes(content)
            {true, nil, size}

          {:error, %{message: message}, _frame} ->
            {false, message, nil}

          _ ->
            {false, "Unknown error", nil}
        end

      user = frame.assigns[:current_user]
      headers = frame.context.headers || []
      auth_method = Sanbase.MCP.Auth.get_auth_method(headers)

      Sanbase.MCP.ToolInvocation.create(%{
        user_id: if(user, do: user.id),
        tool_name: tool_name,
        params: params,
        is_successful: is_successful,
        error_message: error_message,
        response_size_bytes: response_size_bytes,
        duration_ms: duration_ms,
        auth_method: auth_method
      })
    end)
  end

  defp response_size_bytes(content) do
    Jason.encode!(content) |> byte_size()
  rescue
    _ -> nil
  end

  defp assign_current_user(%Anubis.Server.Frame{} = frame) do
    headers = frame.context.headers || %{}

    user =
      frame.assigns[:current_user] ||
        Sanbase.MCP.Auth.headers_list_to_user(headers)

    frame =
      if user do
        assign(frame, :current_user, user)
      else
        frame
      end

    assign(frame, :is_authenticated, not is_nil(user))
  end
end
