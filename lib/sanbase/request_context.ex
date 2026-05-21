defmodule Sanbase.RequestContext do
  @moduledoc """
  Explicit per-request state that replaces the ad-hoc
  `Process.put(:__graphql_query_current_user_id__, …)` and related Logger /
  Sentry side-channels used by the privacy-masking pipeline.

  An instance is built once per request at the edge (HTTP `AuthPlug`,
  MCP `handle_invocation`, Oban worker entry) and threaded explicitly
  through the call graph as a `:context` option. The `privacy_protected`
  flag is decided once at construction by calling
  `Sanbase.Accounts.privacy_protected?/1`; downstream code never
  re-decides.

  See `PLAN.md` for the full migration. The struct is intentionally
  narrow — anything specific to one origin (e.g. Oban job args, AI-chat
  requesting-user-id) lives in dedicated constructors added with that
  phase, not on the shared shape.
  """

  @enforce_keys [:origin]
  defstruct [
    :origin,
    user_id: nil,
    privacy_protected: false,
    auth_method: nil,
    product_code: nil,
    request_id: nil,
    remote_ip: nil
  ]

  @type origin :: :graphql | :mcp | :oban | :script | :system | :anonymous
  @type t :: %__MODULE__{
          user_id: non_neg_integer() | nil,
          privacy_protected: boolean(),
          auth_method: atom() | nil,
          product_code: String.t() | nil,
          request_id: String.t() | nil,
          remote_ip: String.t() | nil,
          origin: origin()
        }

  @spec protected?(t() | term()) :: boolean()
  def protected?(%__MODULE__{privacy_protected: v}), do: v
  def protected?(_), do: false

  @spec from_conn(Plug.Conn.t()) :: t()
  def from_conn(%Plug.Conn{} = conn) do
    auth_struct = conn.private[:san_authentication] || %{}
    auth = Map.get(auth_struct, :auth) || %{}
    user_id = get_in(auth, [:current_user, Access.key(:id)])

    %__MODULE__{
      origin: :graphql,
      user_id: user_id,
      privacy_protected: Sanbase.Accounts.privacy_protected?(user_id),
      auth_method: Map.get(auth, :auth_method),
      product_code: Map.get(auth_struct, :product_code),
      request_id: request_id_from_conn(conn),
      remote_ip: remote_ip_to_string(conn.remote_ip)
    }
  end

  @spec from_absinthe(Absinthe.Resolution.t() | %{context: map()}) :: t() | nil
  def from_absinthe(%{context: %{request_context: %__MODULE__{} = ctx}}), do: ctx
  def from_absinthe(_), do: nil

  @spec from_mcp_frame(map()) :: t()
  def from_mcp_frame(frame) do
    user = get_in(frame, [Access.key(:assigns), :current_user])
    user_id = user && Map.get(user, :id)
    headers = get_in(frame, [Access.key(:context), :headers]) || []

    %__MODULE__{
      origin: :mcp,
      user_id: user_id,
      privacy_protected: Sanbase.Accounts.privacy_protected?(user_id),
      auth_method: mcp_auth_method(headers),
      product_code: "SANAPI",
      request_id: mcp_request_id(headers),
      remote_ip: nil
    }
  end

  @spec anonymous(origin()) :: t()
  def anonymous(origin) when is_atom(origin) do
    %__MODULE__{origin: origin, user_id: nil, privacy_protected: false}
  end

  @spec system(origin(), String.t()) :: t()
  def system(origin, reason) when is_atom(origin) and is_binary(reason) do
    %__MODULE__{
      origin: origin,
      user_id: nil,
      privacy_protected: false,
      auth_method: :system,
      product_code: reason
    }
  end

  defp request_id_from_conn(conn) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [id | _] -> id
      _ -> Keyword.get(Logger.metadata(), :request_id)
    end
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

  defp mcp_request_id(headers) do
    header_value(headers, "mcp-session-id") || header_value(headers, "x-request-id")
  end

  defp header_value(headers, name) do
    case Sanbase.MCP.Auth.get_header(headers, name) do
      {_, value} -> value
      _ -> nil
    end
  end
end
