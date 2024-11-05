defmodule Sanbase.Email.MailjetApi do
  env = Application.compile_env(:sanbase, :env)
  @module if env == :test, do: Sanbase.Email.MailjetApiTest, else: Sanbase.Email.MailjetApiImpl

  def subscribe(list_atom, email_or_emails), do: @module.subscribe(list_atom, email_or_emails)
  def unsubscribe(list_atom, email_or_emails), do: @module.unsubscribe(list_atom, email_or_emails)

  def send_to_list(list_atom, subject, content),
    do: @module.send_to_list(list_atom, subject, content)
end

defmodule Sanbase.Email.MailjetApiTest do
  def subscribe(_, _), do: :ok
  def unsubscribe(_, _), do: :ok
  def send_to_list(_, _, _), do: :ok
end

defmodule Sanbase.Email.MailjetApiImpl do
  require Sanbase.Utils.Config, as: Config
  require Logger

  @base_url "https://api.mailjet.com/v3/REST/"
  @bi_weekly_list_id -1
  @monthly_newsletter_list_id 61_085
  @mailjet_sanr_list_id 10_321_582
  @alpha_naratives_list_id 10_321_590
  @metric_updates_list_id 10_326_520

  @mailjet_lists %{
    bi_weekly: @bi_weekly_list_id,
    monthly_newsletter: @monthly_newsletter_list_id,
    sanr_network_emails: @mailjet_sanr_list_id,
    alpha_naratives_emails: @alpha_naratives_list_id,
    metric_updates: @metric_updates_list_id
  }

  @send_api_url "https://api.mailjet.com/v3.1/send"

  def subscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :subscribe)
  end

  def unsubscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :unsubscribe)
  end

  def send_to_list(list_atom, subject, content) do
    payload = %{
      "Messages" => [
        %{
          "From" => %{
            "Email" => "support@santiment.net",
            "Name" => "Santiment"
          },
          "Subject" => subject,
          "HTMLPart" => content,
          "To" => [],
          "ContactsList" => %{
            "ListID" => @mailjet_lists[list_atom]
          }
        }
      ]
    }

    Req.post!(
      @send_api_url,
      json: payload,
      headers: headers()
    )
    |> case do
      %{status: code} when code in [200, 201] ->
        Logger.info("Email sent to Mailjet list #{list_atom}")
        :ok

      %{status: _code} = response ->
        Logger.error("Error sending email to Mailjet list: #{inspect(response)}")
        {:error, response.body}
    end
  rescue
    error ->
      Logger.error("Error sending email to Mailjet list. Reason: #{inspect(error)}")
      {:error, error}
  end

  # private

  defp subscribe_unsubscribe(list_atom, email_or_emails, action) do
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

  defp manage_subscription(body_json, list_id, action) do
    HTTPoison.post(
      @base_url <> "contactslist/#{list_id}/managemanycontacts",
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

  defp basic_auth do
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
