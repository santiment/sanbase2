defmodule Sanbase.MCP.Server do
  @moduledoc "MCP server for Sanbase metrics access"

  use Anubis.Server,
    name: "sanbase-metrics",
    version: "1.0.0",
    capabilities: [:tools, :prompts, :resources]

  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.ActivityTracesConfig
  alias Sanbase.MCP.{Auth, Restrictions, ToolInvocation}
  alias Sanbase.RequestContext

  @banned_message "Your account is banned from the Santiment MCP server. Contact support."

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    user = Auth.headers_list_to_user(frame.context.headers)
    frame = assign(frame, :current_user, user)
    {:ok, frame |> assign(:is_authenticated, not is_nil(user))}
  end

  @impl true
  def handle_request(%{"method" => "tools/call"} = request, %Anubis.Server.Frame{} = frame) do
    handle_invocation(request, frame, "tool")
  end

  def handle_request(%{"method" => "prompts/get"} = request, %Anubis.Server.Frame{} = frame) do
    handle_invocation(request, frame, "prompt")
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

  # Register chart tool
  component(Sanbase.MCP.ShowChartTool)

  # Register MCP App UI resources
  component(Sanbase.MCP.SocialTrendsUI)
  component(Sanbase.MCP.ChartUI)

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

  defp handle_invocation(request, frame, kind) do
    frame = assign_current_user(frame)
    ctx = RequestContext.from_mcp_frame(frame)
    name = get_in(request, ["params", "name"])
    params = get_in(request, ["params", "arguments"]) || %{}

    case mcp_access_check(frame, name) do
      :ok ->
        with_logger_metadata(ctx, fn ->
          start_time = System.monotonic_time(:millisecond)
          result = Anubis.Server.Handlers.handle(request, __MODULE__, frame)
          duration_ms = System.monotonic_time(:millisecond) - start_time
          track_invocation(result, ctx, name, params, duration_ms, kind)
          result
        end)

      {:banned, frame} ->
        record_banned_attempt(ctx, name, params, kind)
        {:reply, error_response(@banned_message), frame}

      {:rate_limited, error_message} ->
        result = {:reply, error_response(error_message), frame}
        track_invocation(result, ctx, name, params, 0, kind)
        result
    end
  end

  defp with_logger_metadata(%RequestContext{} = ctx, fun) do
    old_metadata = Logger.metadata()
    RequestContext.put_logger_metadata(ctx)

    try do
      fun.()
    after
      restore_logger_metadata(old_metadata)
    end
  end

  defp restore_logger_metadata(old_metadata) do
    old_keys = Keyword.keys(old_metadata)

    reset_metadata =
      Logger.metadata()
      |> Keyword.keys()
      |> Enum.reject(&(&1 in old_keys))
      |> Enum.map(&{&1, nil})

    Logger.metadata(reset_metadata ++ old_metadata)
  end

  defp error_response(message) do
    Anubis.Server.Response.tool()
    |> Anubis.Server.Response.error(message)
    |> Anubis.Server.Response.to_protocol()
  end

  defp mcp_access_check(frame, tool_name) do
    case frame.assigns[:current_user] do
      nil ->
        {:rate_limited,
         "Authentication required to use MCP tools. Please provide a valid API key or OAuth token."}

      user ->
        # Re-check ban flag against the DB so a mid-session ban applies immediately
        # without relying on the user struct cached in frame assigns.
        if User.mcp_banned?(user.id) do
          {:banned, frame}
        else
          check_rate_limits(user, tool_name)
        end
    end
  end

  defp check_rate_limits(user, tool_name) do
    if ToolInvocation.team_member?(user) do
      :ok
    else
      tier = Restrictions.tier_for_user(user)

      with {:ok, _} <- ToolInvocation.check_rate_limit(user.id, tier),
           {:ok, _} <- ToolInvocation.check_tool_rate_limit(user.id, tool_name, tier) do
        :ok
      else
        {:error, message} -> {:rate_limited, message}
      end
    end
  end

  defp track_invocation(result, ctx, tool_name, params, duration_ms, kind) do
    {is_successful, error_message, response_size_bytes} =
      case result do
        {:reply, %{"isError" => true, "content" => content}, _frame} ->
          error_msg =
            content
            |> Enum.map_join("\n", fn item -> item["text"] || "" end)

          size = response_size_bytes(content)
          {false, error_msg, size}

        {:reply, %{"content" => content}, _frame} ->
          size = response_size_bytes(content)
          {true, nil, size}

        {:reply, %{"messages" => messages}, _frame} ->
          size = response_size_bytes(messages)
          {true, nil, size}

        {:error, %{message: message}, _frame} ->
          {false, message, nil}

        _ ->
          {false, "Unknown error", nil}
      end

    persist_tool_invocation(
      ctx,
      build_attrs(ctx, tool_name, params, duration_ms, kind, %{
        is_successful: is_successful,
        error_message: error_message,
        response_size_bytes: response_size_bytes
      })
    )
  end

  defp record_banned_attempt(ctx, tool_name, params, kind) do
    persist_tool_invocation(
      ctx,
      build_attrs(ctx, tool_name, params, 0, kind, %{
        is_successful: false,
        error_message: "banned",
        response_size_bytes: nil
      })
    )
  end

  defp build_attrs(%RequestContext{} = ctx, tool_name, params, duration_ms, kind, outcome) do
    %{
      user_id: ctx.user_id,
      tool_name: tool_name,
      params: params,
      is_successful: outcome.is_successful,
      error_message: outcome.error_message,
      response_size_bytes: outcome.response_size_bytes,
      duration_ms: duration_ms,
      auth_method: ctx.auth_method && Atom.to_string(ctx.auth_method),
      user_agent: ctx.user_agent,
      client: ctx.client,
      session_id: ctx.session_id,
      kind: kind
    }
    |> Sanbase.MCP.Privacy.mask_attrs(
      ActivityTracesConfig.hidden?(:hide_mcp_tool_invocations, ctx)
    )
  end

  # In test, Ecto SQL Sandbox ties DB connections to the test process.
  # Async tasks that outlive the test process lose their connection,
  # causing Postgrex disconnect errors. Run synchronously in test.
  @env Application.compile_env(:sanbase, :env)
  if @env == :test do
    defp persist_tool_invocation(_ctx, attrs) do
      ToolInvocation.create(attrs)
    end
  else
    # Re-seed `Logger.metadata` inside the spawned Task so any incidental
    # logging or ClickHouse activity in `ToolInvocation.create/1` still
    # carries the request's privacy flag. `Task.Supervisor.start_child/2`
    # does not inherit Logger metadata from the caller.
    defp persist_tool_invocation(%RequestContext{} = ctx, attrs) do
      Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
        RequestContext.put_logger_metadata(ctx)
        ToolInvocation.create(attrs)
      end)
    end
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
        Auth.headers_list_to_user(headers)

    frame =
      if user do
        assign(frame, :current_user, user)
      else
        frame
      end

    assign(frame, :is_authenticated, not is_nil(user))
  end
end
