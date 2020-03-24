defmodule Sanbase.Oauth2.Hydra do
  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Product, Subscription, Plan}
  alias Sanbase.GrafanaApi

  def get_access_token() do
    with {:ok, %HTTPoison.Response{body: json_body, status_code: 200}} <- do_fetch_access_token(),
         {:ok, access_token} <- extract_field_from_json(json_body, "access_token") do
      {:ok, access_token}
    else
      error -> Logger.warn("Error getting access_token: " <> inspect(error))
    end
  end

  def get_consent_data(consent, access_token) do
    with {:ok, %HTTPoison.Response{body: json_body, status_code: 200}} <-
           do_fetch_consent_data(consent, access_token),
         {:ok, redirect_url} <- extract_field_from_json(json_body, "redirectUrl"),
         {:ok, client_id} <- extract_field_from_json(json_body, "clientId") do
      {:ok, redirect_url, client_id}
    else
      error -> Logger.warn("Error getting consent data: " <> inspect(error))
    end
  end

  def manage_consent(consent, access_token, user) do
    case Subscription.current_subscription(user, Product.product_sangraphs()) do
      %Subscription{plan: %Plan{id: plan_id}} ->
        find_or_create_grafana_user(user)
        |> case do
          {:ok, %{"id" => grafana_user_id}} ->
            GrafanaApi.add_subscribed_user_to_team(grafana_user_id, plan_id)

            accept_consent(consent, access_token, user)

          {:error, reason} ->
            Logger.error("Error find_or_create_grafana_user: reason #{inspect(reason)}")

            reject_consent(
              consent,
              access_token,
              "Unexpected error occured! Please, try again or contact site administrator."
            )
        end

      nil ->
        error_msg = "#{user.email || user.username} doesn't have an active Sandata subscription"
        Logger.error(error_msg)
        reject_consent(consent, access_token, error_msg)
    end
  end

  # helpers

  defp find_or_create_grafana_user(user) do
    case GrafanaApi.get_user_by_email_or_username(user) do
      {:ok, grafana_user} ->
        {:ok, grafana_user}

      _ ->
        GrafanaApi.create_user(user)
    end
  end

  defp accept_consent(consent, access_token, user) do
    do_accept_consent(consent, access_token, user)
    |> handle_consent_result("accept")
  end

  defp reject_consent(consent, access_token, error_msg) do
    do_reject_consent(consent, access_token, error_msg)
    |> handle_consent_result("reject")
  end

  defp handle_consent_result(result, type) do
    case result do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        {:ok, "Consent #{type} success"}

      error ->
        Logger.warn("Error #{type} consent: " <> inspect(error))
        {:ok, "Consent #{type} error"}
    end
  end

  defp do_fetch_access_token() do
    HTTPoison.post(
      token_url(),
      "grant_type=client_credentials&scope=hydra.consent",
      [{"Accept", "application/json"}, {"content-type", "application/x-www-form-urlencoded"}],
      basic_auth()
    )
  end

  defp do_fetch_consent_data(consent, access_token) do
    HTTPoison.get(consent_url() <> "/#{consent}", [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ])
  end

  defp do_accept_consent(consent, access_token, %User{username: username, id: id, email: email}) do
    data = %{
      "grantScopes" => ["openid", "offline", "hydra.clients"],
      "accessTokenExtra" => %{},
      "idTokenExtra" => %{id: id, name: username, email: email || username},
      "subject" => "user:#{id}:#{username}"
    }

    HTTPoison.patch(consent_url() <> "/#{consent}/accept", Jason.encode!(data), [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-type", "application/json"},
      {"Accept", "application/json"}
    ])
  end

  defp do_reject_consent(
         consent,
         access_token,
         error_msg
       ) do
    data = %{"reason" => error_msg}

    HTTPoison.patch(consent_url() <> "/#{consent}/reject", Jason.encode!(data), [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-type", "application/json"},
      {"Accept", "application/json"}
    ])
  end

  defp extract_field_from_json(json, field) do
    with {:ok, body} <- Jason.decode(json),
         {:ok, result} <- Map.fetch(body, field) do
      {:ok, result}
    end
  end

  defp token_url(), do: Config.get(:base_url) <> Config.get(:token_uri)
  defp consent_url(), do: Config.get(:base_url) <> Config.get(:consent_uri)

  defp basic_auth(),
    do: [hackney: [basic_auth: {Config.get(:client_id), Config.get(:client_secret)}]]
end
