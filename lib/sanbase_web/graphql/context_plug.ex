defmodule SanbaseWeb.Graphql.ContextPlug do
  @moduledoc ~s"""
  Plug that builds the Graphql context.
  Currently only checks the `authorization` header and verifies the credentials
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
      |> add_query_cache_key(conn)
      |> Map.put(:remote_ip, conn.remote_ip)

    put_private(conn, :absinthe, %{context: context})
  end

  defp build_context(conn, [auth_method | rest]) do
    auth_method.(conn)
    |> case do
      :skip -> build_context(conn, rest)
      auth -> %{auth: auth}
    end
  end

  defp build_context(_conn, []), do: %{super_duper_mega_key: 123_123_123_123}

  defp add_query_cache_key(context, %Plug.Conn{
         params: params
       }) do
    query = Map.get(params, "query")

    # TODO: Datetime variables are still strings
    variables =
      case Map.get(params, "variables") do
        x when x in [nil, ""] -> %{}
        vars -> vars |> IO.inspect(label: "VAAAAARSRRSSS") |> Jason.decode!()
      end

    cache_key = SanbaseWeb.Graphql.Cache.cache_key(query, variables)
    Map.put(context, :query_cache_key, cache_key)
  end

  defp add_query_cache_key(context, _), do: context

  def bearer_authentication(%Plug.Conn{} = conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, current_user} <- bearer_authorize(token) do
      %{auth_method: :user_token, current_user: current_user}
    else
      _ -> :skip
    end
  end

  def basic_authentication(%Plug.Conn{} = conn) do
    with ["Basic " <> auth_attempt] <- get_req_header(conn, "authorization"),
         {:ok, current_user} <- basic_authorize(auth_attempt) do
      %{auth_method: :basic, current_user: current_user}
    else
      _ -> :skip
    end
  end

  def apikey_authentication(%Plug.Conn{} = conn) do
    with ["Apikey " <> apikey] <- get_req_header(conn, "authorization"),
         {:ok, current_user} <- apikey_authorize(apikey),
         {:ok, {token, _apikey}} <- Sanbase.Auth.Hmac.split_apikey(apikey) do
      %{auth_method: :apikey, current_user: current_user, token: token}
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
