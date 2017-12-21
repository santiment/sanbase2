defmodule SanbaseWeb.Graphql.ContextPlug do
  @behavior Plug

  import Plug.Conn

  import Sanbase.Utils, only: [parse_config_value: 1]

  alias SanbaseWeb.Graphql.ContextPlug
  alias Sanbase.Auth.User

  require Logger

  @auth_methods [&ContextPlug.bearer_authentication/1, &ContextPlug.basic_authentication/1]

  def init(opts), do: opts

  def call(conn, _) do
    context = build_context(conn, @auth_methods)
    put_private(conn, :absinthe, %{context: context})
  end

  defp build_context(conn, [auth_method|rest]) do
    auth_method.(conn)
    |> case do
      :skip -> build_context(conn, rest)
      auth -> %{auth: auth}
    end
  end

  defp build_context(conn, []), do: %{}

  def bearer_authentication(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
    {:ok, current_user} <- bearer_authorize(token) do
      %{auth_method: :user_token, current_user: current_user}
    else
      _ -> :skip
    end
  end

  def basic_authentication(conn) do
    with ["Basic " <> auth_attempt] <- get_req_header(conn, "authorization"),
    {:ok, current_user} <- basic_authorize(auth_attempt) do
      %{auth_method: :basic, current_user: current_user}
    else
      _ -> :skip
    end
  end

  defp bearer_authorize(token) do
    with {:ok, %User{salt: salt} = user, %{"salt" => salt}} <- SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, user}
    else
      _ ->
        Logger.warn("Invalid bearer token in request: #{token}")
        {:error, :invalid_token}
    end
  end

  defp basic_authorize(auth_attempt) do
    username = config(:basic_auth_username)
    password = config(:basic_auth_password)

    Base.encode64(username <> ":" <> password)
    |> case do
      ^auth_attempt -> {:ok, username}
      _ ->
        Logger.warn("Invalid basic auth credentials in request")
        {:error, :invalid_credentials}
    end
  end

  defp config(key) do
    Application.fetch_env!(:sanbase, __MODULE__)
    |> Keyword.get(key)
    |> parse_config_value()
  end
end
