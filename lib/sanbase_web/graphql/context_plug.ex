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

  @compile {:inline,
            build_context: 2,
            build_error_msg: 1,
            jwt_access_token_authorization: 1,
            jwt_auth_header_authorization: 1,
            bearer_authorize: 2,
            basic_authorization: 1,
            basic_authorize: 1,
            apikey_authorize: 1,
            get_no_auth_product_id: 1,
            get_apikey_product_id: 1,
            san_balance: 1,
            get_origin: 1}

  import Plug.Conn
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.ApiCallLimit
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Product}
  alias SanbaseWeb.Graphql.ContextPlug

  require Logger

  @auth_methods [
    &ContextPlug.jwt_access_token_authorization/1,
    &ContextPlug.jwt_auth_header_authorization/1,
    &ContextPlug.apikey_authorization/1,
    &ContextPlug.basic_authorization/1
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
    conn = maybe_put_new_access_token(conn, context)

    %{origin_host: origin_host, origin_url: origin_url, origin_host_parts: origin_host_parts} =
      get_origin(conn)

    context =
      context
      |> Map.put(:remote_ip, conn.remote_ip)
      |> Map.put(:origin_url, origin_url)
      |> Map.put(:origin_host, origin_host)
      |> Map.put(:origin_host_parts, origin_host_parts)
      |> Map.put(:rate_limiting_enabled, Config.get(:rate_limiting_enabled))
      |> Map.put(:device_data, SanbaseWeb.Guardian.device_data(conn))
      |> Map.put(:jwt_tokens, conn_to_jwt_tokens(conn))
      |> Map.delete(:new_access_token)

    conn = put_private(conn, :absinthe, %{context: context})

    case should_halt?(conn, context, @should_halt_methods) do
      {false, conn} ->
        conn

      {true, conn, error_map} ->
        %{error_msg: error_msg, error_code: error_code} = error_map

        conn
        |> put_resp_content_type("application/json", "charset=utf-8")
        |> send_resp(error_code, build_error_msg(error_msg))
        |> halt()
    end
  end

  defp conn_to_jwt_tokens(conn) do
    %{
      access_token: get_session(conn, :access_token) || get_session(conn, :auth_token),
      refresh_token: get_session(conn, :refresh_token)
    }
  end

  defp maybe_put_new_access_token(conn, context) do
    case Map.has_key?(context, :new_access_token) do
      true ->
        conn
        |> put_session(:auth_token, context.new_access_token)
        |> put_session(:access_token, context.new_access_token)

      false ->
        conn
    end
  end

  defp should_halt?(conn, _context, []), do: {false, conn}

  defp should_halt?(conn, context, [halt_method | rest]) do
    case halt_method.(conn, context) do
      {false, conn} -> should_halt?(conn, context, rest)
      {true, conn, error_map} -> {true, conn, error_map}
    end
  end

  def halt_sansheets_request?(conn, %{
        auth: %{subscription: %{plan: %{name: plan_name}}}
      }) do
    case is_sansheets_request(conn) and plan_name == "FREE" do
      true ->
        error_map = %{
          error_msg: """
          You need to upgrade Sanbase Pro in order to use SanSheets.
          If you already have Sanbase Pro, please make sure that a correct API key is provided.
          """,
          error_code: 401
        }

        {true, conn, error_map}

      false ->
        {false, conn}
    end
  end

  def halt_sansheets_request?(conn, _context), do: {false, conn}

  def halt_api_call_limit_reached?(conn, %{
        rate_limiting_enabled: true,
        product_id: @product_id_api,
        auth: %{current_user: user, auth_method: auth_method}
      }) do
    case ApiCallLimit.get_quota(:user, user, auth_method) do
      {:error, %{blocked_for_seconds: _} = rate_limit_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(rate_limit_map)
          )

        {true, conn, rate_limit_map_to_error_map(rate_limit_map)}

      {:ok, %{quota: :infinity}} ->
        {false, conn}

      {:ok, %{quota: _} = quota_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(quota_map)
          )

        {false, conn}
    end
  end

  def halt_api_call_limit_reached?(
        conn,
        %{
          rate_limiting_enabled: true,
          product_id: @product_id_api,
          remote_ip: remote_ip
        } = context
      ) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)
    auth_method = context[:auth][:auth_method] || :unauthorized

    case ApiCallLimit.get_quota(:remote_ip, remote_ip, auth_method) do
      {:error, %{blocked_for_seconds: _} = rate_limit_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(rate_limit_map)
          )

        {true, conn, rate_limit_map_to_error_map(rate_limit_map)}

      {:ok, %{quota: :infinity}} ->
        {false, conn}

      {:ok, %{quota: _} = quota_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(quota_map)
          )

        {false, conn}
    end
  end

  def halt_api_call_limit_reached?(conn, _context), do: {false, conn}

  defp rate_limit_error_message(%{blocked_for_seconds: seconds}) do
    human_duration = Sanbase.DateTimeUtils.seconds_to_human_readable(seconds)

    """
    API Rate Limit Reached. Try again in #{seconds} seconds (#{human_duration})
    """
  end

  defp rate_limit_headers(map) do
    %{
      api_calls_limits: api_calls_limit,
      api_calls_remaining: api_calls_remaining
    } = map

    headers = [
      {"x-ratelimit-remaining-month", api_calls_remaining.month},
      {"x-ratelimit-remaining-hour", api_calls_remaining.hour},
      {"x-ratelimit-remaining-minute", api_calls_remaining.minute},
      {"x-ratelimit-remaining", api_calls_remaining.minute},
      {"x-ratelimit-limit-month", api_calls_limit.month},
      {"x-ratelimit-limit-hour", api_calls_limit.hour},
      {"x-ratelimit-limit-minute", api_calls_limit.minute},
      {"x-ratelimit-limit", api_calls_limit.minute}
    ]

    case Map.get(map, :blocked_for_seconds) do
      nil ->
        headers

      blocked_for_seconds ->
        [{"x-ratelimit-reset", blocked_for_seconds} | headers]
    end
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

  # TODO: After these changes, the session will now also contain `access_token`
  # insted of only `auth_token`, which is better named and should be used. This
  # is a process of authorization, not authentication
  def jwt_access_token_authorization(%Plug.Conn{} = conn) do
    access_token = get_session(conn, :access_token) || get_session(conn, :auth_token)

    case access_token && bearer_authorize(conn, access_token) do
      {:ok, %{current_user: current_user} = map} ->
        subscription =
          Subscription.current_subscription(current_user.id, @product_id_sanbase) ||
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
        |> Map.merge(Map.take(map, [:new_access_token]))

      {:error, error} ->
        {:error, error}

      _ ->
        :try_next
    end
  end

  def jwt_auth_header_authorization(%Plug.Conn{} = conn) do
    with {_, ["Bearer " <> token]} <- {:has_header?, get_req_header(conn, "authorization")},
         {:ok, %{current_user: current_user} = map} <- bearer_authorize(conn, token) do
      subscription =
        Subscription.current_subscription(current_user.id, @product_id_sanbase) ||
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
      |> Map.merge(Map.take(map, [:new_access_token]))
    else
      {:has_header?, _} -> :try_next
      error -> error
    end
  end

  def basic_authorization(%Plug.Conn{} = conn) do
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

  def apikey_authorization(%Plug.Conn{} = conn) do
    with {_, ["Apikey " <> apikey]} <-
           {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- apikey_authorize(apikey),
         {:ok, {token, _apikey}} <- Sanbase.Accounts.Hmac.split_apikey(apikey) do
      product_id =
        get_req_header(conn, "user-agent")
        |> get_apikey_product_id()

      subscription =
        Subscription.current_subscription(current_user.id, product_id) ||
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
      conn
      |> get_origin()
      |> Map.get(:origin_host)
      |> get_no_auth_product_id()

    Map.put(@anon_user_base_context, :product_id, product_id)
  end

  defp bearer_authorize(conn, token) do
    case SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, %User{} = user, _} ->
        {:ok, %{current_user: user}}

      {:error, :token_expired} ->
        bearer_authorize_refresh_token(conn)

      {:error, :invalid_token} ->
        %{permissions: User.Permissions.no_permissions()}

      _ ->
        {:error, "Invalid JSON Web Token (JWT)"}
    end
  end

  defp bearer_authorize_refresh_token(conn) do
    case try_refresh_token(conn) do
      {:ok, %{current_user: _, new_access_token: _}} = result ->
        result

      _ ->
        %{permissions: User.Permissions.no_permissions()}
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
    Sanbase.Accounts.Apikey.apikey_to_user(apikey)
  end

  defp try_refresh_token(conn) do
    case get_session(conn, :refresh_token) do
      refresh_token when is_binary(refresh_token) ->
        exchange_refresh_for_access_token(refresh_token)

      _ ->
        {:error, :no_refresh_token}
    end
  end

  defp exchange_refresh_for_access_token(refresh_token) do
    opts = [ttl: SanbaseWeb.Guardian.access_token_ttl()]

    case SanbaseWeb.Guardian.exchange(refresh_token, "refresh", "access", opts) do
      {:ok, _old_stuff, {new_access_token, _claims}} ->
        case SanbaseWeb.Guardian.resource_from_token(new_access_token) do
          {:ok, %User{} = user, _} ->
            {:ok, %{current_user: user, new_access_token: new_access_token}}

          _ ->
            {:error, :invalid_new_access_token}
        end

      _ ->
        {:error, :invalid_refresh_token}
    end
  end

  defp san_balance(%User{} = user) do
    case User.san_balance(user) do
      {:ok, balance} -> balance
      _ -> 0
    end
  end

  defp get_no_auth_product_id(nil), do: @product_id_api

  defp get_no_auth_product_id(origin) do
    case String.ends_with?(origin, "santiment.net") do
      true -> @product_id_sanbase
      false -> @product_id_api
    end
  end

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

  defp get_origin(conn) do
    Plug.Conn.get_req_header(conn, "origin")
    |> List.first()
    |> case do
      origin_url when is_binary(origin_url) ->
        # Strip trailing backslashes, ports, etc.
        %URI{host: origin_host} = origin_url |> URI.parse()
        origin_host_parts = String.split(origin_host, ".")

        %{
          origin_host: origin_host,
          origin_url: origin_url,
          origin_host_parts: origin_host_parts
        }

      _ ->
        %{
          origin_host: nil,
          origin_url: nil,
          origin_host_parts: nil
        }
    end
  end

  defp rate_limit_map_to_error_map(rate_limit_map) do
    %{
      error_msg: rate_limit_error_message(rate_limit_map),
      error_code: 429
    }
  end
end
