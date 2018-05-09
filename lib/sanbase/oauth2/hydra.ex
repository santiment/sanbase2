defmodule Sanbase.Oauth2.Hydra do
  import Sanbase.Utils.Config, only: [parse_config_value: 1]

  alias Sanbase.Auth.User

  def get_access_token() do
    HTTPoison.post!(
      token_url(),
      "grant_type=client_credentials&scope=hydra.consent",
      [{"Accept", "application/json"}, {"content-type", "application/x-www-form-urlencoded"}],
      basic_auth()
    )
    |> case do
      %HTTPoison.Response{body: body, status_code: 200} ->
        {:ok, Poison.decode!(body)["access_token"]}

      _ ->
        {:error, "Cannot get access token"}
    end
  end

  def get_consent_data(consent, access_token) do
    HTTPoison.get!(consent_url() <> "/#{consent}", [
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

    HTTPoison.patch!(consent_url() <> "/#{consent}/accept", Poison.encode!(data), [
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

  defp get_config(key) do
    Application.fetch_env!(:sanbase, Sanbase.Hydra)
    |> IO.inspect()
    |> Keyword.fetch!(key)
    |> parse_config_value()
  end

  defp token_url(), do: get_config(:base_url) <> get_config(:token_uri)
  defp consent_url(), do: get_config(:base_url) <> get_config(:consent_uri)

  defp basic_auth(),
    do: [hackney: [basic_auth: {get_config(:client_id), get_config(:client_secret)}]]
end
