defmodule Sanbase.Email.MailjetApi do
  require Sanbase.Utils.Config, as: Config
  require Logger

  @base_url "https://api.mailjet.com/v3/REST/"
  @bi_weekly_list_id -1
  @monthly_newsletter_list_id 61085

  @mailjet_lists %{
    bi_weekly: @bi_weekly_list_id,
    monthly_newsletter: @monthly_newsletter_list_id
  }

  def subscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :subscribe)
  end

  def unsubscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :unsubscribe)
  end

  def subscribe_unsubscribe(list_atom, email_or_emails, action) do
    action_map = %{subscribe: "addnoforce", unsubscribe: "remove"}

    contacts =
      email_or_emails
      |> List.wrap()
      |> Enum.map(fn email -> %{"Email" => email} end)

    %{
      "Contacts" => contacts,
      "Action" => action_map[action]
    }
    |> Jason.encode!()
    |> manage_subscription(@mailjet_lists[list_atom], action)
  end

  def manage_subscription(body_json, list_id, action) do
    HTTPoison.post(
      @base_url() <> "contactslist/#{list_id}/managemanycontacts",
      body_json,
      headers()
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 201}} ->
        Logger.info("Email #{action} to Mailjet: #{body_json}")
        :ok

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error #{action} email to Mailjet: #{inspect(body_json)}}. Response: #{inspect(response)}"
        )

        {:error, response.body}

      {:error, reason} ->
        Logger.error(
          "Error #{action} email to Mailjet : #{body_json}}. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def basic_auth do
    Base.encode64(
      Config.module_get!(Sanbase.TemplateMailer, :api_key) <>
        ":" <> Config.module_get!(Sanbase.TemplateMailer, :secret)
    )
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Basic #{basic_auth()}"}
    ]
  end
end
