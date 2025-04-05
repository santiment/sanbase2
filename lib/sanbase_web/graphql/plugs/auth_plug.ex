defmodule SanbaseWeb.Graphql.AuthPlug.AuthStruct do
  defstruct permissions: nil,
            auth: nil,
            product_id: nil,
            product_code: nil,
            new_access_token: nil,
            requested_product_id: nil,
            requested_product: nil,
            subscription_product_id: nil,
            subscription_product: nil
end

defmodule SanbaseWeb.Graphql.AuthPlug do
  @moduledoc ~s"""
  Plug that handles the authentication

  It performs the following operations:
  - Check the `Authorization` header and verifies the credentials. Basic auth,
  JSON Web Token (JWT) and apikey are the supported credential mechanisms.
  - Inject the permissions for the logged in or anonymous user. The permissions
  are a simple map that marks if the user has access to historical and realtime data
  """

  @behaviour Plug

  @compile {:inline,
            authenticate: 2,
            build_error_msg: 1,
            jwt_access_token_authentication: 1,
            jwt_auth_header_authentication: 1,
            bearer_authenticate: 2,
            basic_authentication: 1,
            basic_authenticate: 1,
            apikey_authenticate: 1,
            get_no_auth_product_id: 1,
            get_apikey_product_id: 1}

  import Plug.Conn

  alias SanbaseWeb.Graphql.AuthPlug
  alias SanbaseWeb.Graphql.AuthPlug.AuthStruct
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Chart.Configuration.SharedAccessToken

  require Logger
  require Sanbase.Utils.Config, as: Config

  defguard no_auth_header(header) when header in [[], ["null"], [""], nil]

  @authentication_methods [
    &AuthPlug.jwt_access_token_authentication/1,
    &AuthPlug.jwt_auth_header_authentication/1,
    &AuthPlug.apikey_authentication/1,
    &AuthPlug.basic_authentication/1
  ]

  @augmenting_auth_methods [
    &AuthPlug.augment_auth_with_shared_access_token/2
  ]

  @product_id_api Product.product_api()
  @product_id_sanbase Product.product_sanbase()

  @anon_user_auth_struct %AuthStruct{
    permissions: User.Permissions.no_permissions(),
    auth: %{
      auth_method: :none,
      subscription: nil,
      plan: "FREE"
    },
    product_id: nil,
    product_code: nil,
    requested_product_id: nil,
    subscription_product_id: nil
  }
  def init(opts), do: opts

  def call(conn, _) do
    conn = conn |> put_private(:origin_url_map, get_origin(conn))

    case authenticate(conn, @authentication_methods) do
      {:ok, %AuthStruct{} = auth_struct} ->
        auth_struct = augment_auth(auth_struct, conn)

        conn
        |> maybe_put_new_access_token(auth_struct)
        |> put_private(:san_authentication, Map.from_struct(auth_struct))

      {:error, error_msg} ->
        conn
        |> send_resp(400, build_error_msg(error_msg))
        |> halt()
    end
  end

  # Extend the auth struct with some extra information. This is
  # not the core authentication logic, but rather some additional
  # logic that only extends the core logic.
  # For example, the auth struct can be extended with a `shared access token`
  # which gives access to the metrics on a chart layout
  defp augment_auth(%AuthStruct{} = auth_struct, %Plug.Conn{} = conn) do
    @augmenting_auth_methods
    |> Enum.reduce(auth_struct, fn augment_auth_method, auth_struct_acc ->
      %AuthStruct{} = augment_auth_method.(auth_struct_acc, conn)
    end)
  end

  # Authenticate the user using the X-SharedAccess-Authorization header. It
  # contains a token that, when resolved, gives access to some metrics and
  # queries that are used in a chart layout. This authentication only augments
  # the existing auth_struct by adding new fields to it. This is not a main
  # authentication method but should be used only on some pages.
  def augment_auth_with_shared_access_token(%AuthStruct{} = auth_struct, %Plug.Conn{} = conn) do
    with ["SharedAccessToken " <> uuid] <- get_req_header(conn, "x-sharedaccess-authorization"),
         {:ok, sat} <- SharedAccessToken.by_uuid(uuid),
         {:ok, resolved_sat} <- SharedAccessToken.get_resolved_token(sat) do
      Map.put(auth_struct, :resolved_shared_access_token, resolved_sat)
    else
      _ ->
        auth_struct
    end
  end

  defp maybe_put_new_access_token(%Plug.Conn{} = conn, %AuthStruct{} = auth_struct) do
    case Map.get(auth_struct, :new_access_token) do
      nil ->
        conn

      access_token ->
        conn
        |> put_session(:access_token, access_token)
    end
  end

  defp build_error_msg(msg) do
    %{errors: %{details: msg}} |> Jason.encode!()
  end

  defp authenticate(conn, [auth_method | rest]) do
    case auth_method.(conn) do
      :try_next ->
        authenticate(conn, rest)

      {:error, error_msg} ->
        {:error, error_msg}

      %AuthStruct{} = auth_struct ->
        {:ok, auth_struct}
    end
  end

  defp authenticate(conn, []) do
    case get_req_header(conn, "authorization") do
      header when no_auth_header(header) ->
        # If there is no authentication method that succeeded
        # but also there is no authentication header, then the
        # request is coming from an anonymous user.
        {:ok, anon_user_auth_struct(conn)}

      [header] ->
        error_msg = """
        Unsupported authorization header value: #{inspect(header)}.
        The supported formats of the authorization header are:
          "Bearer <JWT>"
          "Apikey <apikey>"
          "Basic <basic>"
        """

        {:error, error_msg}
    end
  end

  def jwt_access_token_authentication(%Plug.Conn{} = conn) do
    access_token = get_session(conn, :access_token)

    case access_token && bearer_authenticate(conn, access_token) do
      {:ok, %{current_user: current_user} = map} ->
        # This will fetch the subscription of the primary user, if any is linked.
        # If there is no primary user linked it will return the subscription of the
        # current user
        subscription = get_user_subscription_for_sanbase(current_user.id)
        subscription_product_id = if subscription, do: subscription.plan.product_id, else: nil

        subscription_product =
          if subscription, do: Product.code_by_id(subscription.plan.product_id), else: nil

        %AuthStruct{
          permissions: User.Permissions.permissions(current_user),
          auth: %{
            auth_method: :user_token,
            current_user: current_user,
            subscription: subscription,
            plan: Subscription.plan_name(subscription)
          },
          requested_product_id: @product_id_sanbase,
          requested_product: "SANBASE",
          subscription_product_id: subscription_product_id,
          subscription_product: subscription_product
        }
        |> Map.merge(Map.take(map, [:new_access_token]))

      {:error, error} ->
        {:error, error}

      _ ->
        :try_next
    end
  end

  def jwt_auth_header_authentication(%Plug.Conn{} = conn) do
    with {_, ["Bearer " <> token]} <- {:has_header?, get_req_header(conn, "authorization")},
         {:ok, %{current_user: current_user} = map} <- bearer_authenticate(conn, token) do
      requested_product_id = @product_id_sanbase
      requested_product = "SANBASE"
      subscription = find_best_subscription(requested_product_id, current_user.id)
      subscription_product_id = if subscription, do: subscription.plan.product_id, else: nil

      subscription_product =
        if subscription, do: Product.code_by_id(subscription.plan.product_id), else: nil

      %AuthStruct{
        permissions: User.Permissions.permissions(current_user),
        auth: %{
          auth_method: :user_token,
          current_user: current_user,
          subscription: subscription,
          plan: Subscription.plan_name(subscription)
        },
        requested_product_id: requested_product_id,
        requested_product: requested_product,
        product_code: requested_product,
        subscription_product_id: subscription_product_id,
        subscription_product: subscription_product
      }
      |> Map.merge(Map.take(map, [:new_access_token]))
    else
      {:has_header?, _} ->
        # There is authentication header, but it does not start with Bearer
        :try_next

      error ->
        error
    end
  end

  def basic_authentication(%Plug.Conn{} = conn) do
    with {_, ["Basic " <> auth_attempt]} <- {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- basic_authenticate(auth_attempt) do
      %AuthStruct{
        permissions: User.Permissions.full_permissions(),
        auth: %{
          auth_method: :basic,
          current_user: current_user,
          subscription: nil,
          plan: nil
        },
        requested_product_id: @product_id_api,
        requested_product: "SANAPI",
        product_code: "SANAPI"
      }
    else
      {:has_header?, _} ->
        :try_next

      _ ->
        # Do not error on wrong basic auth. This prevents issues when developing
        # locally. It is also not a used user-flow in produciton, so not
        # returning an error here won't hurt much.
        anon_user_auth_struct(conn)
    end
  end

  def apikey_authentication(%Plug.Conn{} = conn) do
    with {_, ["Apikey " <> apikey]} <- {:has_header?, get_req_header(conn, "authorization")},
         {:ok, current_user} <- apikey_authenticate(apikey),
         {:ok, {token, _apikey}} <- Sanbase.Accounts.Hmac.split_apikey(apikey) do
      requested_product_id =
        get_req_header(conn, "user-agent")
        |> get_apikey_product_id()

      subscription = find_best_subscription(requested_product_id, current_user.id)
      subscription_product_id = if subscription, do: subscription.plan.product_id, else: nil

      subscription_product =
        if subscription, do: Product.code_by_id(subscription.plan.product_id), else: nil

      %AuthStruct{
        permissions: User.Permissions.permissions(current_user),
        auth: %{
          auth_method: :apikey,
          current_user: current_user,
          token: token,
          subscription: subscription,
          plan: Subscription.plan_name(subscription)
        },
        subscription_product_id: subscription_product_id,
        subscription_product: subscription_product,
        requested_product_id: requested_product_id,
        requested_product: Product.code_by_id(requested_product_id),
        product_code: Product.code_by_id(requested_product_id)
      }
    else
      # There is an authentication header, but it does not start with `Bearer`
      {:has_header?, _} -> :try_next
      error -> error
    end
  end

  # Private functions

  defp find_best_subscription(requested_product, user_id) do
    api_sub = Subscription.current_subscription(user_id, @product_id_api)
    sanbase_sub = Subscription.current_subscription(user_id, @product_id_sanbase)

    case Product.code_by_id(requested_product) do
      "SANBASE" -> sanbase_sub || api_sub
      "SANAPI" -> api_sub || sanbase_sub
    end
  end

  defp get_user_subscription(user_id, product) do
    # If there is an account linked, get the subscription of the
    # primary user. Otherwise, get the subscription of that user.

    case Subscription.get_user_subscription(user_id, product) do
      {:ok, subscription} -> subscription
      {:error, _} -> nil
    end
  end

  defp get_user_subscription_for_sanbase(user_id) do
    get_user_subscription(user_id, @product_id_sanbase) ||
      get_user_subscription(user_id, @product_id_api)
  end

  defp anon_user_auth_struct(conn) do
    product_id =
      conn.private[:origin_url_map]
      |> Map.get(:origin_host)
      |> get_no_auth_product_id()

    @anon_user_auth_struct
    |> Map.merge(%{
      requested_product_id: product_id,
      requested_product: Product.code_by_id(product_id),
      product_code: Product.code_by_id(product_id)
    })
  end

  defp bearer_authenticate(conn, token) do
    case SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, %User{} = user, _} ->
        {:ok, %{current_user: user}}

      {:error, :token_expired} ->
        bearer_authenticate_refresh_token(conn)

      {:error, :invalid_token} ->
        {:error, "Invalid JSON Web Token (JWT)"}

      _error ->
        {:error, "Invalid JSON Web Token (JWT)"}
    end
  end

  defp bearer_authenticate_refresh_token(conn) do
    case try_refresh_token(conn) do
      {:ok, %{current_user: _, new_access_token: _}} = result ->
        result

      _ ->
        %{permissions: User.Permissions.no_permissions()}
    end
  end

  defp basic_authenticate(auth_attempt) do
    username = Config.module_get(__MODULE__, :basic_auth_username)
    password = Config.module_get(__MODULE__, :basic_auth_password)

    case Base.encode64(username <> ":" <> password) do
      ^auth_attempt ->
        # Put roles as [] otherwise we get Ecto.Association.NotLoaded error
        # when computing moderator and superuser
        {:ok, %User{is_superuser: true, roles: []}}

      _ ->
        {:error, "Invalid basic authentication header credentials"}
    end
  end

  defp apikey_authenticate(apikey) do
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

  defp get_no_auth_product_id(nil), do: @product_id_api

  defp get_no_auth_product_id(origin) do
    case String.ends_with?(origin, "santiment.net") or
           String.ends_with?(origin, "santiment.network") or
           String.ends_with?(origin, "sanr.app") or
           String.ends_with?(origin, "sanitize.page") do
      true -> @product_id_sanbase
      false -> @product_id_api
    end
  end

  # FIXME - maybe treat sansheets as still API
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
        origin_host_parts = String.split(origin_host || "", ".")

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
end
