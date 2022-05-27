defmodule SanbaseWeb.Graphql.ContextPlug do
  @moduledoc ~s"""
  Plug that builds the GraphQL context.

  It performs the following operations:
  - Check the `Authorization` header and verifies the credentials. Basic auth,
  JSON Web Token (JWT) and apikey are the supported credential mechanisms.
  - Inject the permissions for the logged in or anonymous user. The permissions
  are a simple map that marks if the user has access to historical and realtime data
  """

  @behaviour Plug

  @compile {:inline, conn_to_jwt_tokens: 1}

  import Plug.Conn
  require Sanbase.Utils.Config, as: Config

  def init(opts), do: opts

  def call(conn, _) do
    auth_struct = conn.private[:san_authentication]

    %{origin_host: origin_host, origin_url: origin_url, origin_host_parts: origin_host_parts} =
      conn.private[:origin_url_map]

    context =
      auth_struct
      |> put_is_san_moderator_flag()
      |> Map.put(:remote_ip, conn.remote_ip)
      |> Map.put(:origin_url, origin_url)
      |> Map.put(:origin_host, origin_host)
      |> Map.put(:origin_host_parts, origin_host_parts)
      |> Map.put(:rate_limiting_enabled, Config.module_get(__MODULE__, :rate_limiting_enabled))
      |> Map.put(:device_data, SanbaseWeb.Guardian.device_data(conn))
      |> Map.put(:jwt_tokens, conn_to_jwt_tokens(conn))
      |> Map.delete(:new_access_token)

    put_private(conn, :absinthe, %{context: context})
  end

  defp put_is_san_moderator_flag(context) do
    with %{auth: %{current_user: %{id: user_id}}} <- context,
         {:ok, moderator_ids} <-
           Sanbase.Cache.get_or_store(:get_san_moderator_ids, fn ->
             {:ok, Sanbase.Accounts.Role.san_moderator_ids()}
           end) do
      context
      |> Map.put(:is_san_moderator, user_id in moderator_ids)
    else
      _ ->
        context
        |> Map.put(:is_san_moderator, false)
    end
  rescue
    _ ->
      context
      |> Map.put(:is_san_moderator, false)
  end

  defp conn_to_jwt_tokens(conn) do
    %{
      access_token: get_session(conn, :access_token) || get_session(conn, :auth_token),
      refresh_token: get_session(conn, :refresh_token)
    }
  end
end
