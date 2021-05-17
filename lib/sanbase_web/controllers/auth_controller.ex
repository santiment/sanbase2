defmodule SanbaseWeb.AccountsController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

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

    email = auth.info.email

    with true <- is_binary(email),
         {:ok, user} <-
           User.find_or_insert_by(:email, email, %{login_origin: :google}),
         {:ok, %{} = jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user),
         {:ok, _} <- User.mark_as_registered(user, %{login_origin: :google}) do
      conn
      |> put_jwt_tokens_in_session(jwt_tokens_map)
      |> redirect(external: redirect_urls.success)
    else
      _ ->
        conn
        |> redirect(external: redirect_urls.fail)
    end
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :twitter} = auth}} = conn, params) do
    redirect_urls = get_redirect_urls(params)

    twitter_id = auth.uid
    email = auth.info.email

    with {:ok, user} <- twitter_login(email, twitter_id),
         {:ok, %{} = jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user),
         {:ok, _} <- User.mark_as_registered(user, %{login_origin: :twitter}) do
      conn
      |> put_jwt_tokens_in_session(jwt_tokens_map)
      |> redirect(external: redirect_urls.success)
    else
      _ ->
        conn
        |> redirect(external: redirect_urls.fail)
    end
  end

  defp put_jwt_tokens_in_session(conn, jwt_tokens_map) do
    conn
    |> put_session(:auth_token, jwt_tokens_map.access_token)
    |> put_session(:access_token, jwt_tokens_map.access_token)
    |> put_session(:refresh_token, jwt_tokens_map.refresh_token)
  end

  # In case the twitter profile has an email address, try fetching the user with
  # that email and set its twitter_id to the given id. This is done so existing
  # account can be linked to a twitter account when email addresses match.
  # The User.update_twitter_id/2 is no-op if the user with that email already exists and
  # has that twitter_id set. So this results in a single DB call in all cases
  # except the first time twitter login is used.
  defp twitter_login(email, twitter_id) when is_binary(email) and byte_size(email) > 0 do
    with {:ok, user} <-
           User.find_or_insert_by(:email, email, %{is_registered: true, login_origin: :twitter}),
         {:ok, user} <- User.update_field(user, :twitter_id, twitter_id) do
      {:ok, user}
    end
  end

  defp twitter_login(_email, twitter_id) do
    User.find_or_insert_by(:twitter_id, twitter_id, %{is_registered: true, login_origin: :twitter})
  end

  defp get_redirect_urls(%{"state" => state}) do
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
