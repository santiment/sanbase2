defmodule Sanbase.Email.MailjetApiBehaviour do
  @callback subscribe(atom(), String.t() | [String.t()]) :: :ok | {:error, term()}
  @callback unsubscribe(atom(), String.t() | [String.t()]) :: :ok | {:error, term()}
  @callback send_to_list(atom(), String.t(), String.t(), Keyword.t()) :: :ok | {:error, term()}
  @callback list_subscribed_emails(atom()) :: {:ok, [String.t()]} | {:error, term()}
  @callback send_email(String.t(), String.t(), String.t(), Keyword.t()) :: :ok | {:error, term()}
end

defmodule Sanbase.Email.MailjetApi do
  @behaviour Sanbase.Email.MailjetApiBehaviour

  require Sanbase.Utils.Config, as: Config
  require Logger

  @base_url "https://api.mailjet.com/v3/REST/"
  @bi_weekly_list_id -1
  @monthly_newsletter_list_id 61_085
  @mailjet_sanr_list_id 10_321_582
  @alpha_naratives_list_id 10_321_590
  @metric_updates_list_id 10_326_520
  @dev_metric_updates_list_id 10_326_671
  @stage_metric_updates_list_id 10_326_676

  @mailjet_lists %{
    bi_weekly: @bi_weekly_list_id,
    monthly_newsletter: @monthly_newsletter_list_id,
    sanr_network_emails: @mailjet_sanr_list_id,
    alpha_naratives_emails: @alpha_naratives_list_id,
    metric_updates: @metric_updates_list_id,
    metric_updates_dev: @dev_metric_updates_list_id,
    metric_updates_stage: @stage_metric_updates_list_id
  }
  @send_api_url "https://api.mailjet.com/v3.1/send"

  def client do
    Application.get_env(:sanbase, :mailjet_api, __MODULE__)
  end

  def subscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :subscribe)
  end

  def unsubscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :unsubscribe)
  end

  def send_to_list(list_id, subject, content, opts \\ []) do
    with {:ok, emails} <- list_subscribed_emails(list_id),
         :ok <- Enum.each(emails, &send_email(&1, subject, content, opts)) do
      :ok
    end
  end

  def send_email(email, subject, content, opts \\ []) do
    html_content = if Keyword.get(opts, :html, false), do: content, else: nil
    text_content = if html_content, do: nil, else: content

    payload = %{
      "Messages" => [
        %{
          "From" => %{
            "Email" => "support@santiment.net",
            "Name" => "Santiment"
          },
          "Subject" => subject,
          "HTMLPart" => html_content,
          "TextPart" => text_content,
          "To" => [
            %{
              "Email" => email
            }
          ]
        }
      ]
    }

    case Req.post!(@send_api_url, json: payload, headers: headers()) do
      %{status: status} when status in 200..299 ->
        Logger.info("Email sent successfully to #{email}")
        :ok

      response ->
        Logger.error("Failed to send email to #{email}. Response: #{inspect(response)}")
        {:error, response}
    end
  rescue
    error ->
      Logger.error("Error sending email to #{email}. Reason: #{inspect(error)}")
      {:error, error}
  end

  # list subscribed emails for list
  def list_subscribed_emails(list_atom) do
    with {:ok, contact_ids} <- get_contact_ids(list_atom),
         {:ok, emails} <- get_emails_for_contacts(contact_ids) do
      {:ok, emails}
    end
  end

  defp get_contact_ids(list_atom) do
    Req.get!(
      @base_url <> "listrecipient?ContactsList=#{@mailjet_lists[list_atom]}&Limit=1000",
      headers: headers()
    )
    |> case do
      %{status: 200, body: %{"Data" => recipients}} ->
        contact_ids = Enum.map(recipients, & &1["ContactID"])
        {:ok, contact_ids}

      %{status: _code} = response ->
        Logger.error("Error fetching contact IDs from Mailjet list: #{inspect(response)}")
        {:error, response.body}
    end
  rescue
    error ->
      Logger.error("Error fetching contact IDs from Mailjet list. Reason: #{inspect(error)}")
      {:error, error}
  end

  defp get_emails_for_contacts(contact_ids) do
    emails_with_results = Enum.map(contact_ids, &get_email_for_contact/1)

    # Filter out any errors and just collect successful emails
    emails =
      emails_with_results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, email} -> email end)

    {:ok, emails}
  end

  defp get_email_for_contact(contact_id) do
    Req.get!(
      @base_url <> "contact/#{contact_id}",
      headers: headers()
    )
    |> case do
      %{status: 200, body: %{"Data" => [contact | _]}} ->
        {:ok, contact["Email"]}

      %{status: _code} = response ->
        Logger.error("Error fetching email for contact #{contact_id}: #{inspect(response)}")
        {:error, response.body}
    end
  rescue
    error ->
      Logger.error("Error fetching email for contact #{contact_id}. Reason: #{inspect(error)}")
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
