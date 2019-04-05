defmodule SanbaseWeb.Graphql.ContextPlug do
  @moduledoc ~s"""
  Plug that builds the GraphQL context.

  It performs the following operations:
  - Check the `Authorization` header and verifies the credentials. Basic auth,
  JSON Web Token (JWT) and apikey are the supported credential mechanisms.
  - Inject the permissions for the logged in or anonymous user. The permissions
  are a simple map that marks if the user has access to historical and realtime data
  - Inject the cache key for the query in the context.
  """

  @behaviour Plug

  import Plug.Conn
  require Sanbase.Utils.Config, as: Config

  alias SanbaseWeb.Graphql.ContextPlug
  alias Sanbase.Auth.User

  require Logger

  @auth_methods [
    &ContextPlug.bearer_authentication/1,
    &ContextPlug.basic_authentication/1,
    &ContextPlug.apikey_authentication/1
  ]

  def init(opts), do: opts

  def call(conn, _) do
    context =
      build_context(conn, @auth_methods)
      |> Map.put(:remote_ip, conn.remote_ip)

    put_private(conn, :absinthe, %{context: context})
  end

  defp build_context(conn, [auth_method | rest]) do
    auth_method.(conn)
    |> case do
      :skip ->
        build_context(conn, rest)

      context ->
        context
    end
  end

  defp build_context(_conn, []), do: %{permissions: User.no_permissions()}

  def bearer_authentication(%Plug.Conn{} = conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, current_user} <- bearer_authorize(token) do
      %{
        permissions: User.permissions!(current_user),
        auth: %{
          auth_method: :user_token,
          current_user: current_user
        }
      }
    else
      _ -> :skip
    end
  end

  def basic_authentication(%Plug.Conn{} = conn) do
    with ["Basic " <> auth_attempt] <- get_req_header(conn, "authorization"),
         {:ok, current_user} <- basic_authorize(auth_attempt) do
      %{
        permissions: User.full_permissions(),
        auth: %{auth_method: :basic, current_user: current_user}
      }
    else
      _ -> :skip
    end
  end

  def apikey_authentication(%Plug.Conn{} = conn) do
    with ["Apikey " <> apikey] <- get_req_header(conn, "authorization"),
         {:ok, current_user} <- apikey_authorize(apikey),
         {:ok, {token, _apikey}} <- Sanbase.Auth.Hmac.split_apikey(apikey) do
      %{
        permissions: User.permissions!(current_user),
        auth: %{auth_method: :apikey, current_user: current_user, token: token}
      }
    else
      _ -> :skip
    end
  end

  defp bearer_authorize(token) do
    with {:ok, %User{salt: salt} = user, %{"salt" => salt}} <-
           SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, user}
    else
      _ ->
        Logger.warn("Invalid bearer token in request: #{token}")
        {:error, :invalid_token}
    end
  end

  defp basic_authorize(auth_attempt) do
    username = Config.get(:basic_auth_username)
    password = Config.get(:basic_auth_password)

    Base.encode64(username <> ":" <> password)
    |> case do
      ^auth_attempt ->
        {:ok, username}

      _ ->
        Logger.warn("Invalid basic auth credentials in request")
        {:error, :invalid_credentials}
    end
  end

  defp apikey_authorize(apikey) do
    Sanbase.Auth.Apikey.apikey_to_user(apikey)
  end
end
