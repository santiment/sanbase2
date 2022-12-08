defmodule SanbaseWeb.AccountsController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  plug(Ueberauth)

  alias Sanbase.Accounts.User

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :google} = auth}} = conn, params) do
    redirect_urls = get_redirect_urls(params)
    device_data = SanbaseWeb.Guardian.device_data(conn)
    email = auth.info.email
    origin_url = Plug.Conn.get_req_header(conn, "host")
    args = %{login_origin: :google, origin_url: origin_url}

    with true <- is_binary(email),
         {:ok, user} <- User.find_or_insert_by(:email, email, args),
         {:ok, %{} = jwt_tokens_map} <-
           SanbaseWeb.Guardian.get_jwt_tokens(user,
             platform: device_data.platform,
             client: device_data.client
           ),
         {:ok, _} <- User.mark_as_registered(user, args) do
      emit_event({:ok, user}, :login_user, args)

      conn
      |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(jwt_tokens_map)
      |> redirect(external: redirect_urls.success)
    else
      _ ->
        conn
        |> redirect(external: redirect_urls.fail)
    end
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :twitter} = auth}} = conn, params) do
    redirect_urls = get_redirect_urls(params)
    device_data = SanbaseWeb.Guardian.device_data(conn)

    twitter_id = auth.uid
    email = auth.info.email
    origin_url = Plug.Conn.get_req_header(conn, "host")
    args = %{login_origin: :twitter, origin_url: origin_url}

    with {:ok, user} <- twitter_login(email, twitter_id),
         {:ok, %{} = jwt_tokens_map} <-
           SanbaseWeb.Guardian.get_jwt_tokens(user,
             platform: device_data.platform,
             client: device_data.client
           ),
         {:ok, _} <- User.mark_as_registered(user, args) do
      emit_event({:ok, user}, :login_user, args)

      conn
      |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(jwt_tokens_map)
      |> redirect(external: redirect_urls.success)
    else
      _ ->
        conn
        |> redirect(external: redirect_urls.fail)
    end
  end

  defp twitter_login(email, twitter_id) when is_binary(email) and byte_size(email) > 0 do
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
        {:ok, user}

      _ ->
        # If there is not user with that twitter_id then fetch or create a user with that email
        # and put the twitter_id.
        args = %{is_registered: true, login_origin: :twitter}

        with {:ok, user} <- User.find_or_insert_by(:email, email, args),
             is_registered <- user.is_registered,
             {:ok, user} <- User.update_field(user, :twitter_id, twitter_id) do
          {:ok, %{user | first_login: not is_registered}}
        end
    end
  end

  defp twitter_login(_email, twitter_id) do
    User.find_or_insert_by(:twitter_id, twitter_id, %{is_registered: true, login_origin: :twitter})
  end

  defp get_redirect_urls(%{"san_redirects_state" => state}) do
    website_url = SanbaseWeb.Endpoint.website_url()

    map =
      state
      |> Base.decode64!()
      |> Jason.decode!()

    %{
      success: Map.get(map, "success_redirect_url", website_url),
      fails: Map.get(map, "fail_redirect_url", website_url)
    }
    |> Enum.into(%{}, fn {key, url} ->
      # Use the state provided redirects only if they're form the santiment host
      with %URI{host: host} <- URI.parse(url),
           ["santiment", "net"] <- host |> String.split(".") |> Enum.take(-2) do
        {key, url}
      else
        _ -> {key, website_url}
      end
    end)
  end

  defp get_redirect_urls(_params) do
    website_url = SanbaseWeb.Endpoint.website_url()

    %{
      success: website_url,
      fail: website_url
    }
  end
end
