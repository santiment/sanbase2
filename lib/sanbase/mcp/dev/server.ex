defmodule Sanbase.MCP.Dev.Server do
  @moduledoc """
  Team-only MCP server for development and data exploration, served at `/mcp_dev`:
  read-only ClickHouse SQL with the BUSINESS_MAX plan's table access, and raw social
  messages from metrics-hub.

  `handle_request/2` re-checks access so a routing mistake cannot expose it.
  """

  use Anubis.Server,
    name: "santiment-dev",
    version: "1.0.0",
    capabilities: [:tools]

  require Logger

  alias Sanbase.Accounts.ActivityTracesConfig
  alias Sanbase.Accounts.User
  alias Sanbase.MCP.{Auth, Privacy, ToolError, ToolInvocation}
  alias Sanbase.MCP.Dev.Access
  alias Sanbase.RequestContext

  @required_scope "mcp:dev"
  @rate_limit_scale_ms :timer.minutes(1)
  @default_rate_limit_per_minute 60
  @max_logged_detail_length 2_000

  component(Sanbase.MCP.Dev.ListTablesTool)
  component(Sanbase.MCP.Dev.DescribeTablesTool)
  component(Sanbase.MCP.Dev.ExecuteSqlTool)
  component(Sanbase.MCP.Dev.SocialMessagesTool)
  component(Sanbase.MCP.Dev.TweetsByAuthorTool)

  @doc """
  Log a dev MCP tool call while respecting `ActivityTracesConfig` and sanitizing
  user-controlled arguments with `inspect/1` and truncation.
  """
  @spec log_tool_call(User.t(), String.t(), term()) :: :ok
  def log_tool_call(%User{id: user_id}, tool_name, detail) when is_binary(tool_name) do
    if ActivityTracesConfig.hidden?(:hide_logger, RequestContext.current()) do
      Logger.info("[MCP Dev] User #{user_id} #{tool_name}")
    else
      sanitized = detail |> inspect() |> String.slice(0, @max_logged_detail_length)
      Logger.info("[MCP Dev] User #{user_id} #{tool_name}: #{sanitized}")
    end
  end

  @impl true
  def server_instructions() do
    """
    Santiment's internal dev tools for the team.

    ClickHouse SQL (read-only, with the access of a SanAPI BUSINESS_MAX subscription):
    1. `list_tables` to find tables (optionally filtered by a name substring).
    2. `describe_tables` for the columns, types and sorting keys of the tables you will use.
    3. `execute_sql` to run a query. Filter on the sorting key columns, always add a LIMIT,
       and prefer aggregates over raw rows. Parameters use the `{{name}}` syntax.

    Social data: `social_messages` returns a stratified sample of raw social posts about a
    coin plus a stats block computed over all matching posts. `tweets_by_author` returns
    every indexed post by one X account in a window (only accounts Santiment tracks).
    Both can return large results: process them from a file or with a cheaper model.
    """
  end

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    {:ok, assign_current_user(frame)}
  end

  @impl true
  def handle_request(%{"method" => "tools/call"} = request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)
    user = frame.assigns[:current_user]

    if Access.allowed?(user) do
      handle_invocation(request, frame, user)
    else
      {:error, Anubis.MCP.Error.protocol(:invalid_request, %{message: Access.denied_message()}),
       frame}
    end
  end

  def handle_request(%{"method" => method} = request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)

    if Access.allowed?(frame.assigns[:current_user]) or method == "ping" do
      ctx = RequestContext.from_mcp_frame(frame)

      with_request_context(ctx, fn ->
        Anubis.Server.Handlers.handle(request, __MODULE__, frame)
      end)
    else
      {:error, Anubis.MCP.Error.protocol(:invalid_request, %{message: Access.denied_message()}),
       frame}
    end
  end

  defp handle_invocation(request, frame, user) do
    ctx = RequestContext.from_mcp_frame(frame)
    name = get_in(request, ["params", "name"])
    params = get_in(request, ["params", "arguments"]) || %{}

    case check_rate_limit(user.id) do
      :ok ->
        with_request_context(ctx, fn ->
          start_time = System.monotonic_time(:millisecond)
          result = Anubis.Server.Handlers.handle(request, __MODULE__, frame)
          duration_ms = System.monotonic_time(:millisecond) - start_time
          track_invocation(result, ctx, name, params, duration_ms)
          result
        end)

      {:error, message} ->
        result = {:reply, error_response(ToolError.transient(message)), frame}
        track_invocation(result, ctx, name, params, 0)
        result
    end
  end

  defp check_rate_limit(user_id) do
    limit =
      Application.get_env(
        :sanbase,
        :mcp_dev_rate_limit_per_minute,
        @default_rate_limit_per_minute
      )

    case Sanbase.RateLimit.hit("mcp_dev:user:#{user_id}", @rate_limit_scale_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        retry_after_sec = max(div(retry_after_ms, 1000), 1)

        {:error,
         "Dev MCP rate limit exceeded (#{limit} calls/minute). Retry in #{retry_after_sec}s."}
    end
  end

  defp error_response(message) do
    Anubis.Server.Response.tool()
    |> Anubis.Server.Response.error(message)
    |> Anubis.Server.Response.to_protocol()
  end

  defp track_invocation(result, ctx, tool_name, params, duration_ms) do
    {is_successful, error_message, response_size_bytes} =
      case result do
        {:reply, %{"isError" => true, "content" => content}, _frame} ->
          error_msg = Enum.map_join(content, "\n", fn item -> item["text"] || "" end)
          {false, error_msg, response_size_bytes(content)}

        {:reply, %{"content" => content}, _frame} ->
          {true, nil, response_size_bytes(content)}

        {:error, %{message: message}, _frame} ->
          {false, message, nil}

        _ ->
          {false, "Unknown error", nil}
      end

    attrs =
      %{
        user_id: ctx.user_id,
        tool_name: tool_name,
        params: params,
        is_successful: is_successful,
        error_message: error_message,
        response_size_bytes: response_size_bytes,
        duration_ms: duration_ms,
        auth_method: ctx.auth_method && Atom.to_string(ctx.auth_method),
        user_agent: ctx.user_agent,
        client: ctx.client,
        session_id: ctx.session_id,
        kind: "tool",
        server: "mcp_dev"
      }
      |> Privacy.mask_attrs(ActivityTracesConfig.hidden?(:hide_mcp_tool_invocations, ctx))

    persist_tool_invocation(ctx, attrs)
  end

  @env Application.compile_env(:sanbase, :env)
  if @env == :test do
    defp persist_tool_invocation(_ctx, attrs) do
      ToolInvocation.create(attrs)
    end
  else
    defp persist_tool_invocation(%RequestContext{} = ctx, attrs) do
      case Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
             RequestContext.put_logger_metadata(ctx)
             ToolInvocation.create(attrs)
           end) do
        {:ok, _pid} ->
          :ok

        other ->
          Logger.error(
            "Failed to start MCP dev tool-invocation persistence task: #{inspect(other)}"
          )

          :ok
      end
    end
  end

  defp response_size_bytes(content) do
    Jason.encode!(content) |> byte_size()
  rescue
    _ -> nil
  end

  # As in Sanbase.MCP.Server: user_id in CH log_comment and hidden-traces masking.
  defp with_request_context(%RequestContext{} = ctx, fun) do
    old_metadata = Logger.metadata()
    RequestContext.put_logger_metadata(ctx)

    try do
      fun.()
    after
      Logger.reset_metadata(old_metadata)
    end
  end

  defp assign_current_user(%Anubis.Server.Frame{} = frame) do
    headers = frame.context.headers || []

    user =
      if Auth.has_authorization_header?(headers) do
        Auth.headers_list_to_user(headers, required_scope: @required_scope)
      else
        reload_user(frame.assigns[:current_user])
      end

    frame
    |> assign(:current_user, user)
    |> assign(:is_authenticated, not is_nil(user))
  end

  defp reload_user(%User{id: id}) when is_integer(id) do
    case User.by_id(id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp reload_user(_), do: nil
end
