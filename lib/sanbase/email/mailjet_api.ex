defmodule Sanbase.Email.MailjetApiBehaviour do
  @callback subscribe(atom(), String.t() | [String.t()]) :: :ok | {:error, term()}
  @callback unsubscribe(atom(), String.t() | [String.t()]) :: :ok | {:error, term()}
  @callback send_to_list(atom(), String.t(), String.t(), Keyword.t()) :: :ok | {:error, term()}
  @callback fetch_list_emails(atom()) :: {:ok, [String.t()]} | {:error, term()}
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
    with {:ok, emails} <- fetch_list_emails(list_id),
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

  @doc """
  Fetches all emails in a Mailjet list using the contacts API.
  """
  def fetch_list_emails(list_atom) do
    list_id = @mailjet_lists[list_atom]
    url = @base_url <> "contact"

    case Req.get!(url,
           headers: headers(),
           params: [ContactsList: list_id, limit: 1000]
         ) do
      %{status: 200, body: %{"Data" => data}} ->
        emails = Enum.map(data, & &1["Email"])
        Logger.info("Successfully fetched #{length(emails)} emails from list #{list_atom}")
        {:ok, emails}

      %{status: _status} = response ->
        Logger.error("Error fetching emails from Mailjet list #{list_atom}: #{inspect(response)}")
        {:error, response.body}
    end
  rescue
    error ->
      Logger.error(
        "Error fetching emails from Mailjet list #{list_atom}. Reason: #{inspect(error)}"
      )

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
