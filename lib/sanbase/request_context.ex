defmodule Sanbase.RequestContext do
  @moduledoc """
  Explicit per-request state for the privacy-masking pipeline.

  Built once per request at the edge (HTTP `AuthPlug`, MCP
  `MCP.Server.with_logger_metadata`) and threaded explicitly to call
  sites that have it — most importantly via the `:context` option to
  `Sanbase.Clickhouse.Query.new/3`. Explicit threading is preferred: it
  makes the masking decision visible at the call site, removes a hidden
  cross-process dependency, and survives process boundaries (`Task`,
  `Dataloader.KV`, `Sanbase.Parallel`) without depending on metadata
  re-seeding.

  Call sites that haven't been migrated yet fall back to `current/0`,
  which reads `Logger.metadata[:request_context]` seeded at the edge.
  The fallback is transitional — aim to remove it once every CH-issuing
  path threads the struct.

  The `activity_traces_hidden` flag is decided once at construction by
  calling `Sanbase.Accounts.activity_traces_hidden?/1`; downstream code
  never re-decides.
  """

  @enforce_keys [:origin]
  defstruct [
    :origin,
    user_id: nil,
    activity_traces_hidden: false,
    auth_method: nil,
    product_code: nil,
    request_id: nil,
    session_id: nil,
    remote_ip: nil,
    user_agent: nil,
    client: nil
  ]

  @type origin :: :graphql | :mcp | :oban | :script | :system | :anonymous
  @type t :: %__MODULE__{
          user_id: non_neg_integer() | nil,
          activity_traces_hidden: boolean(),
          auth_method: atom() | nil,
          product_code: String.t() | nil,
          request_id: String.t() | nil,
          session_id: String.t() | nil,
          remote_ip: String.t() | nil,
          user_agent: String.t() | nil,
          client: String.t() | nil,
          origin: origin()
        }

  @spec activity_traces_hidden?(t() | term()) :: boolean()
  def activity_traces_hidden?(%__MODULE__{activity_traces_hidden: v}), do: v
  def activity_traces_hidden?(_), do: false

  @doc """
  Ambient request context for code paths that haven't been migrated to thread
  `:context` explicitly. Read from `Logger.metadata()[:request_context]` —
  populated at the edge (AuthPlug, MCP `with_request_context`) and cleared by
  `SanbaseWeb.Plug.RequestContextPlug` on the next Cowboy request, so worker
  reuse can't leak a stale value into a different request.

  Always returns a struct: falls back to `anonymous(:system)` outside any
  request scope (background jobs, Oban, scripts).
  """
  @spec current() :: t()
  def current() do
    case Logger.metadata()[:request_context] do
      %__MODULE__{} = ctx -> ctx
      _ -> anonymous(:system)
    end
  end

  @doc """
  Seeds Logger.metadata with the request context plus a `:user_id`
  shorthand the project's log formatter consumes. Called once at every
  request edge — `AuthPlug` for HTTP, `MCP.Server.with_request_context`
  for MCP.
  """
  @spec put_logger_metadata(t()) :: :ok
  def put_logger_metadata(%__MODULE__{} = ctx) do
    Logger.metadata(user_id: ctx.user_id || "anonymous", request_context: ctx)
  end

  @spec from_conn(Plug.Conn.t()) :: t()
  def from_conn(%Plug.Conn{} = conn) do
    auth_struct = conn.private[:san_authentication] || %{}
    auth = Map.get(auth_struct, :auth) || %{}
    user_id = get_in(auth, [:current_user, Access.key(:id)])

    %__MODULE__{
      origin: :graphql,
      user_id: user_id,
      activity_traces_hidden: Sanbase.Accounts.activity_traces_hidden?(user_id),
      auth_method: Map.get(auth, :auth_method),
      product_code: Map.get(auth_struct, :product_code),
      request_id: Keyword.get(Logger.metadata(), :request_id),
      remote_ip: remote_ip_to_string(conn.remote_ip)
    }
  end

  @spec from_mcp_frame(map()) :: t()
  def from_mcp_frame(frame) do
    assigns = Map.get(frame, :assigns, %{}) || %{}
    context = Map.get(frame, :context, %{}) || %{}
    headers = Map.get(context, :headers, []) || []
    client_info = Map.get(context, :client_info)
    user = Map.get(assigns, :current_user)
    user_id = user && Map.get(user, :id)
    ua_header = header_value(headers, "user-agent")

    %__MODULE__{
      origin: :mcp,
      user_id: user_id,
      activity_traces_hidden: Sanbase.Accounts.activity_traces_hidden?(user_id),
      auth_method: mcp_auth_method(headers),
      product_code: "SANAPI",
      request_id: header_value(headers, "x-request-id"),
      session_id: header_value(headers, "mcp-session-id"),
      remote_ip: Map.get(context, :remote_ip) |> remote_ip_to_string(),
      user_agent:
        ua_header || Sanbase.MCP.ToolInvocation.user_agent_from_client_info(client_info),
      client: Sanbase.MCP.ToolInvocation.derive_client(ua_header, client_info)
    }
  end

  @origins [:graphql, :mcp, :oban, :script, :system, :anonymous]

  @spec anonymous(origin()) :: t()
  def anonymous(origin) when origin in @origins do
    %__MODULE__{origin: origin, user_id: nil, activity_traces_hidden: false}
  end

  defp remote_ip_to_string(nil), do: nil
  defp remote_ip_to_string(ip) when is_tuple(ip), do: Sanbase.Utils.IP.ip_tuple_to_string(ip)
  defp remote_ip_to_string(ip) when is_binary(ip), do: ip
  defp remote_ip_to_string(_), do: nil

  # The atom set is bounded to what `Sanbase.MCP.Auth.get_auth_method/1`
  # can return — never `String.to_atom/1` on the raw value, otherwise
  # any future return string would silently grow the VM atom table.
  defp mcp_auth_method(headers) do
    case Sanbase.MCP.Auth.get_auth_method(headers) do
      "apikey" -> :apikey
      "oauth" -> :oauth
      _ -> nil
    end
  end

  defp header_value(headers, name) do
    case Sanbase.MCP.Auth.get_header(headers, name) do
      {_, value} -> value
      _ -> nil
    end
  end
end
