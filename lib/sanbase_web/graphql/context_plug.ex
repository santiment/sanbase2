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

  @compile :inline_list_funcs
  @compile {:inline,
            build_context: 2,
            build_error_msg: 1,
            bearer_auth_token_authentication: 1,
            bearer_auth_header_authentication: 1,
            bearer_authorize: 1,
            basic_authentication: 1,
            basic_authorize: 1,
            apikey_authorize: 1,
            get_no_auth_product_id: 1,
            get_apikey_product_id: 1,
            san_balance: 1}

  import Plug.Conn
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Product}
  alias SanbaseWeb.Graphql.ContextPlug

  require Logger

  @auth_methods [
    &ContextPlug.bearer_auth_token_authentication/1,
    &ContextPlug.bearer_auth_header_authentication/1,
    &ContextPlug.basic_authentication/1,
    &ContextPlug.apikey_authentication/1
  ]

  @product_id_api Product.product_api()
  @product_id_sanbase Product.product_sanbase()
  @free_subscription Subscription.free_subscription()
  @anon_user_base_context %{
    permissions: User.Permissions.no_permissions(),
    auth: %{
      auth_method: :none,
      san_balance: 0,
      subscription: @free_subscription,
      plan: Subscription.plan_name(@free_subscription)
    }
  }
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
        product_id =
          get_req_header(conn, "origin")
          |> get_no_auth_product_id()

        {conn, Map.put(@anon_user_base_context, :product_id, product_id)}

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
  def bearer_auth_token_authentication(%Plug.Conn{
        private: %{plug_session: %{"auth_token" => token}}
      }) do
    case bearer_authorize(token) do
      {:ok, current_user} ->
        subscription =
          Subscription.current_subscription(current_user, @product_id_sanbase) ||
            Subscription.current_subscription(current_user, @product_id_api) ||
            @free_subscription

        %{
          permissions: User.Permissions.permissions(current_user),
          auth: %{
            auth_method: :user_token,
            current_user: current_user,
            san_balance: san_balance(current_user),
            subscription: subscription,
            plan: Subscription.plan_name(subscription)
          },
          product_id: @product_id_sanbase
        }

      _ ->
        :try_next
    end
  end

  def bearer_auth_token_authentication(_), do: :try_next

  def bearer_auth_header_authentication(%Plug.Conn{} = conn) do
    with {:has_header?, ["Bearer " <> token]} <-
           {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- bearer_authorize(token) do
      subscription =
        Subscription.current_subscription(current_user, @product_id_sanbase) ||
          Subscription.current_subscription(current_user, @product_id_api) ||
          @free_subscription

      %{
        permissions: User.Permissions.permissions(current_user),
        auth: %{
          auth_method: :user_token,
          current_user: current_user,
          san_balance: san_balance(current_user),
          subscription: subscription,
          plan: Subscription.plan_name(subscription)
        },
        product_id: @product_id_sanbase
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
        permissions: User.Permissions.full_permissions(),
        auth: %{
          auth_method: :basic,
          current_user: current_user,
          san_balance: 0,
          subscription: nil,
          plan: nil
        },
        product_id: @product_id_api
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
      product_id =
        get_req_header(conn, "user-agent")
        |> get_apikey_product_id()

      subscription =
        Subscription.current_subscription(current_user, product_id) ||
          @free_subscription

      %{
        permissions: User.Permissions.permissions(current_user),
        auth: %{
          auth_method: :apikey,
          current_user: current_user,
          token: token,
          san_balance: san_balance(current_user),
          subscription: subscription,
          plan: Subscription.plan_name(subscription)
        },
        product_id: product_id
      }
    else
      {:has_header?, _} -> :try_next
      error -> error
    end
  end

  defp bearer_authorize(token) do
    Sanbase.Cache.get_or_store(
      {__MODULE__, :bearer_authorize, token} |> :erlang.phash2(),
      fn ->
        case SanbaseWeb.Guardian.resource_from_token(token) do
          {:ok, %User{salt: salt} = user, %{"salt" => salt}} ->
            {:ok, user}

          {:error, :token_expired} ->
            %{permissions: User.Permissions.no_permissions()}

          {:error, :invalid_token} ->
            %{permissions: User.Permissions.no_permissions()}

          _ ->
            {:error, "Invalid JSON Web Token (JWT)"}
        end
      end
    )
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
    Sanbase.Cache.get_or_store(
      {__MODULE__, :apikey_authorize, apikey} |> :erlang.phash2(),
      fn -> Sanbase.Auth.Apikey.apikey_to_user(apikey) end
    )
  end

  defp san_balance(%User{} = user) do
    case User.san_balance(user) do
      {:ok, balance} -> balance
      _ -> 0
    end
  end

  defp get_no_auth_product_id([origin]) do
    case String.ends_with?(origin, "santiment.net") do
      true -> @product_id_sanbase
      false -> @product_id_api
    end
  end

  defp get_no_auth_product_id(_), do: @product_id_api

  defp get_apikey_product_id([user_agent]) do
    case String.contains?(user_agent, "Google-Apps-Script") do
      true -> @product_id_sanbase
      false -> @product_id_api
    end
  end

  defp get_apikey_product_id(_), do: @product_id_api
end
