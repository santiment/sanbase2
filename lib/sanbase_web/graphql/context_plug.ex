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
    {conn, context} = build_context(conn, @auth_methods)

    context =
      context
      |> Map.put(:remote_ip, conn.remote_ip)
      |> Map.put(:origin_url, Plug.Conn.get_req_header(conn, "origin") |> List.first())

    conn
    |> put_private(:absinthe, %{context: context})
  end

  defp build_error_msg(msg) do
    %{errors: %{details: msg}} |> Jason.encode!()
  end

  defguard no_auth_header(header) when header in [[], ["null"], [""], nil]

  defp build_context(conn, [auth_method | rest]) do
    auth_method.(conn)
    |> case do
      :try_next ->
        build_context(conn, rest)

      {:error, error} ->
        msg = "Bad authorization header: #{error}"
        Logger.warn(msg)

        conn =
          conn
          |> send_resp(400, build_error_msg(msg))
          |> halt()

        {conn, %{}}

      context ->
        {conn, context}
    end
  end

  defp build_context(conn, []) do
    case get_req_header(conn, "authorization") do
      header when no_auth_header(header) ->
        {conn, %{permissions: User.no_permissions()}}

      [header] ->
        Logger.warn("Unsupported authorization header value: #{inspect(header)}")

        response_msg =
          build_error_msg("""
          Unsupported authorization header value: #{inspect(header)}.
          The supported formats of the authorization header are:
            "Bearer <JWT>"
            "Apikey <apikey>"
            "Basic <basic>"
          """)

        conn =
          conn
          |> send_resp(400, response_msg)
          |> halt()

        {conn, %{}}
    end
  end

  # Authenticate with token in cookie
  def bearer_authentication(%Plug.Conn{private: %{plug_session: %{"auth_token" => token}}}) do
    case bearer_authorize(token) do
      {:ok, current_user} ->
        %{
          permissions: User.permissions!(current_user),
          auth: %{
            auth_method: :user_token,
            current_user: current_user
          }
        }

      _ ->
        :try_next
    end
  end

  def bearer_authentication(%Plug.Conn{} = conn) do
    with {:has_header?, ["Bearer " <> token]} <-
           {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- bearer_authorize(token) do
      %{
        permissions: User.permissions!(current_user),
        auth: %{
          auth_method: :user_token,
          current_user: current_user
        }
      }
    else
      {:has_header?, _} -> :try_next
      error -> error
    end
  end

  def basic_authentication(%Plug.Conn{} = conn) do
    with {:has_header?, ["Basic " <> auth_attempt]} <-
           {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- basic_authorize(auth_attempt) do
      %{
        permissions: User.full_permissions(),
        auth: %{auth_method: :basic, current_user: current_user}
      }
    else
      {:has_header?, _} -> :try_next
      error -> error
    end
  end

  def apikey_authentication(%Plug.Conn{} = conn) do
    with {:has_header?, ["Apikey " <> apikey]} <-
           {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- apikey_authorize(apikey),
         {:ok, {token, _apikey}} <- Sanbase.Auth.Hmac.split_apikey(apikey) do
      %{
        permissions: User.permissions!(current_user),
        auth: %{auth_method: :apikey, current_user: current_user, token: token}
      }
    else
      {:has_header?, _} -> :try_next
      error -> error
    end
  end

  defp bearer_authorize(token) do
    with {:ok, %User{salt: salt} = user, %{"salt" => salt}} <-
           SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, user}
    else
      {:error, :token_expired} ->
        %{permissions: User.no_permissions()}

      _ ->
        {:error, "Invalid JSON Web Token (JWT)"}
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
        {:error, "Invalid basic authorization header credentials"}
    end
  end

  defp apikey_authorize(apikey) do
    Sanbase.Auth.Apikey.apikey_to_user(apikey)
  end
end
