defmodule Sanbase.Oauth2.Hydra do
  alias Sanbase.Auth.User

  @base_url "http://localhost:4444"
  @token_url @base_url <> "/oauth2/token"
  @consent_url @base_url <> "/oauth2/consent/requests"
  @client_id "grafana"
  @client_secret "grafana-secret"

  @basic_auth [hackney: [basic_auth: {@client_id, @client_secret}]]

  def get_access_token() do
    HTTPoison.post!(
      @token_url,
      "grant_type=client_credentials&scope=hydra.consent",
      [{"Accept", "application/json"}, {"content-type", "application/x-www-form-urlencoded"}],
      @basic_auth
    )
    |> case do
      %HTTPoison.Response{body: body, status_code: 200} ->
        {:ok, Poison.decode!(body)["access_token"]}

      _ ->
        {:error, "Cannot get access token"}
    end
  end

  def get_consent_data(consent, access_token) do
    HTTPoison.get!(@consent_url <> "/#{consent}", [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ])
    |> case do
      %HTTPoison.Response{body: body, status_code: 200} ->
        {:ok, Poison.decode!(body)["redirectUrl"]}

      _ ->
        {:error, "Cannot get request url"}
    end
  end

  def accept_consent(
        consent,
        access_token,
        %User{username: username, id: id, email: email} = _user
      ) do
    data = %{
      "grantScopes" => ["openid", "offline", "hydra.clients"],
      "accessTokenExtra" => %{},
      "idTokenExtra" => %{name: username, email: email || username},
      "subject" => "user:#{id}:#{username}"
    }

    HTTPoison.patch!(@consent_url <> "/#{consent}/accept", Poison.encode!(data), [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-type", "application/json"},
      {"Accept", "application/json"}
    ])
    |> case do
      %HTTPoison.Response{status_code: 204} ->
        :ok

      _ ->
        :error
    end
  end
end
