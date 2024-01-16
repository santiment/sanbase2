defmodule SanbaseWeb.AuthController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts
  alias Sanbase.Accounts.User

  require Logger

  @providers %{
    "google" => Application.compile_env(:ueberauth, [Ueberauth, :providers, :google]),
    "twitter" => Application.compile_env(:ueberauth, [Ueberauth, :providers, :twitter])
  }

  def request(conn, %{"provider" => provider} = params) do
    # Do not `use Ueberauth` but create a custom `request/2` action that adds a few
    # parameters to the session before invoking the `callback/2` action. This allows
    # state sharing between the request and the callback phases, which gives us the
    # option to dynamically configure via parameters the redirect URLs and the real
    # origin URL

    referer_url = Plug.Conn.get_req_header(conn, "referer") |> List.first()
    referer_url = referer_url || SanbaseWeb.Endpoint.website_url()

    success_redirect_url = get_redirect_url(params, "success_redirect_url", referer_url)

    fail_redirect_url = get_redirect_url(params, "fail_redirect_url", referer_url)

    origin_url =
      referer_url |> URI.parse() |> Map.merge(%{fragment: nil, path: nil}) |> URI.to_string()

    conn
    |> put_session(:__san_success_redirect_url, success_redirect_url)
    |> put_session(:__san_fail_redirect_url, fail_redirect_url)
    |> put_session(:__san_origin_url, origin_url)
    |> Ueberauth.run_request(provider, @providers[provider])
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> redirect(to: "/")
  end

  def callback(conn, %{"provider" => "google"}) do
    %{assigns: %{ueberauth_auth: auth}} =
      conn
      |> Ueberauth.run_callback("google", @providers["google"])

    email = auth.info.email
    device_data = SanbaseWeb.Guardian.device_data(conn)
    origin_url = get_session(conn, :__san_origin_url)
    args = %{login_origin: :google, origin_url: origin_url}

    with true <- is_binary(email) and byte_size(email) > 0,
         {:ok, %{first_login: first_login} = user} <- User.find_or_insert_by(:email, email, args),
         {:ok, _, user} <-
           Accounts.forward_registration(user, "google_oauth", args),
         {:ok, %{} = jwt_tokens_map} <-
           SanbaseWeb.Guardian.get_jwt_tokens(user, device_data) do
      emit_event({:ok, user}, :login_user, args)

      redirect_url = get_session(conn, :__san_success_redirect_url)
      redirect_url = extend_if_first_login(redirect_url, first_login)

      conn
      |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(jwt_tokens_map)
      |> redirect(external: redirect_url)
    else
      _ ->
        conn
        |> redirect(external: get_session(conn, :__san_fail_redirect_url))
    end
  end

  def callback(conn, %{"provider" => "twitter"}) do
    %{assigns: %{ueberauth_auth: auth}} =
      conn
      |> Ueberauth.run_callback("twitter", @providers["twitter"])

    %{uid: twitter_id, info: %{email: email}} = auth
    device_data = SanbaseWeb.Guardian.device_data(conn)
    origin_url = get_session(conn, :__san_origin_url)
    args = %{login_origin: :twitter, origin_url: origin_url}

    with {:ok, user, first_login} <- twitter_login(email, twitter_id),
         {:ok, _, user} <- Accounts.forward_registration(user, "twitter_oauth", args),
         {:ok, %{} = jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data) do
      emit_event({:ok, user}, :login_user, args)

      redirect_url = get_session(conn, :__san_success_redirect_url)
      redirect_url = extend_if_first_login(redirect_url, first_login)

      conn
      |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(jwt_tokens_map)
      |> redirect(external: redirect_url)
    else
      _ ->
        conn
        |> redirect(external: get_session(conn, :__san_fail_redirect_url))
    end
  end

  defp extend_if_first_login(redirect_url, first_login) do
    case first_login do
      true ->
        redirect_url
        |> URI.parse()
        |> URI.append_query("signup=true")
        |> URI.to_string()

      false ->
        redirect_url
    end
  end

  defp twitter_login(email, twitter_id)
       when is_binary(email) and byte_size(email) > 0 do
    # There are 2 cases: The user has their email address visible AFTER
    # their first sanbase login. In this case this operation might fail - the find_or_insert_by/3
    # will return a new user but the update_field/3 will fail as another user will have the same
    # twitter_id

    case User.by_selector(%{twitter_id: twitter_id}) do
      {:ok, user} ->
        # The email might be missing in the database if user has been created in the past but
        # at that point the email address was not visible.
        # This could succeed or fail, depending on the existence of another user with the same email.
        # Regardless of the success of this operation, the login succeeds.
        _ = User.Email.update_email(user, email)
        {:ok, user, _first_login = false}

      _ ->
        # If there is not user with that twitter_id then fetch or create a user with that email
        # and put the twitter_id.
        args = %{login_origin: :twitter}

        with {:ok, %{first_login: first_login} = user} <-
               User.find_or_insert_by(:email, email, args),
             {:ok, user} <- User.update_field(user, :twitter_id, twitter_id) do
          {:ok, user, first_login}
        end
    end
  end

  defp twitter_login(_email, twitter_id) do
    case User.find_or_insert_by(:twitter_id, twitter_id, %{login_origin: :twitter}) do
      {:ok, %{first_login: first_login} = user} -> {:ok, user, first_login}
      error -> error
    end
  end

  defp get_redirect_url(params, url_key, referer_url) do
    url = params[url_key] || referer_url || SanbaseWeb.Endpoint.website_url()

    # In case the provided redirect URL is not valid, simply redirect to sanbase
    case validate_redirect_url(url) do
      true -> url
      _ -> SanbaseWeb.Endpoint.website_url()
    end
  end

  @valid_subomains ["app", "insights", "api", "queries", "sheets", "local"]
  @valid_redirect_hosts @valid_subomains
                        |> Enum.flat_map(&[&1, &1 <> "-stage"])
                        |> Enum.map(&(&1 <> ".santiment.net"))
                        |> List.insert_at(0, "santiment.net")

  case Application.compile_env(:sanbase, :env) do
    :prod ->
      :ok

    env when env in [:dev, :test] ->
      @valid_redirect_hosts ["localhost" | @valid_redirect_hosts]
  end

  defp validate_redirect_url(url) do
    case URI.parse(url) do
      %URI{host: host} when host in @valid_redirect_hosts ->
        true

      _ ->
        Logger.warning("Attempt to redirect to an unsupported endpoint after login: #{url}")
        {:error, "Invalid redirect URL"}
    end
  end
end
