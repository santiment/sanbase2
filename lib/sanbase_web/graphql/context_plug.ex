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

  alias Sanbase.ApiCallLimit
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Product}
  alias SanbaseWeb.Graphql.ContextPlug

  require Logger

  @auth_methods [
    &ContextPlug.bearer_auth_token_authentication/1,
    &ContextPlug.bearer_auth_header_authentication/1,
    &ContextPlug.apikey_authentication/1,
    &ContextPlug.basic_authentication/1
  ]

  @should_halt_methods [
    &ContextPlug.halt_sansheets_request?/2,
    &ContextPlug.halt_api_call_limit_reached?/2
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

    conn =
      conn
      |> put_private(:absinthe, %{context: context})

    rate_limiting_enabled? = Config.get(:rate_limiting_enabled?)

    case rate_limiting_enabled? and should_halt?(conn, context, @should_halt_methods) do
      false ->
        conn

      %{
        error_msg: error_msg,
        error_code: error_code,
        extra_headers: extra_headers
      } ->
        conn
        |> Sanbase.Utils.Conn.put_extra_resp_headers(extra_headers)
        |> put_resp_content_type("application/json", "charset=utf-8")
        |> send_resp(error_code, build_error_msg(error_msg))
        |> halt()
    end
  end

  defp should_halt?(_conn, _context, []), do: false

  defp should_halt?(conn, context, [halt_method | rest]) do
    case halt_method.(conn, context) do
      false -> should_halt?(conn, context, rest)
      error -> error
    end
  end

  def halt_sansheets_request?(conn, %{auth: %{subscription: %{plan: %{name: plan_name}}}}) do
    case is_sansheets_request(conn) and plan_name == "FREE" do
      true ->
        %{
          error_msg: "You need to upgrade to Sanbase Pro in order to use SanSheets.",
          error_code: 401,
          extra_headers: []
        }

      false ->
        false
    end
  end

  def halt_sansheets_request?(_, _), do: false

  def halt_api_call_limit_reached?(_conn, %{
        product_id: @product_id_api,
        auth: %{current_user: user, auth_method: auth_method}
      }) do
    case ApiCallLimit.get_quota(:user, user, auth_method) do
      {:error, %{blocked_for_seconds: blocked_for_seconds}} ->
        extra_headers = [
          {"X-RateLimit-Reset", blocked_for_seconds}
        ]

        %{error_msg: "API Rate Limit Reached", error_code: 429, extra_headers: extra_headers}

      {:ok, _} ->
        false
    end
  end

  def halt_api_call_limit_reached?(
        _conn,
        %{
          product_id: @product_id_api,
          remote_ip: remote_ip
        } = context
      ) do
    remote_ip = remote_ip |> :inet_parse.ntoa() |> to_string()
    auth_method = context[:auth][:auth_method] || :unauthorized

    case ApiCallLimit.get_quota(:remote_ip, remote_ip, auth_method) do
      {:error, %{blocked_for_seconds: blocked_for_seconds}} ->
        %{error_msg: "API Rate Limit Reached", error_code: 429, extra_headers: []}

      {:ok, _} ->
        false
    end
  end

  def halt_api_call_limit_reached?(_conn, _context), do: false

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
        {conn, anon_user_base_context(conn)}

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
    with {_, ["Bearer " <> token]} <- {:has_header?, get_req_header(conn, "authorization")},
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
    case get_req_header(conn, "authorization") do
      ["Basic " <> auth_attempt] ->
        case basic_authorize(auth_attempt) do
          {:ok, current_user} ->
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

          _ ->
            # Do not error on wrong basic auth. This prevents issues when developing
            # locally. It is also not a used user-flow in produciton, so not
            # returning an error here won't hurt much.
            anon_user_base_context(conn)
        end

      _ ->
        :try_next
    end
  end

  def apikey_authentication(%Plug.Conn{} = conn) do
    with {_, ["Apikey " <> apikey]} <- {:has_header?, get_req_header(conn, "authorization")},
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

  defp anon_user_base_context(conn) do
    product_id =
      get_req_header(conn, "origin")
      |> get_no_auth_product_id()

    Map.put(@anon_user_base_context, :product_id, product_id)
  end

  defp bearer_authorize(token) do
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

  defp basic_authorize(auth_attempt) do
    username = Config.get(:basic_auth_username)
    password = Config.get(:basic_auth_password)

    Base.encode64(username <> ":" <> password)
    |> case do
      ^auth_attempt ->
        {:ok, %User{is_superuser: true}}

      _ ->
        {:error, "Invalid basic authorization header credentials"}
    end
  end

  defp apikey_authorize(apikey) do
    Sanbase.Auth.Apikey.apikey_to_user(apikey)
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

  defp is_sansheets_request(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent] -> String.contains?(user_agent, "Google-Apps-Script")
      _ -> false
    end
  end

  defp get_apikey_product_id([user_agent]) do
    case String.contains?(user_agent, "Google-Apps-Script") do
      true -> @product_id_sanbase
      false -> @product_id_api
    end
  end

  defp get_apikey_product_id(_), do: @product_id_api
end
