defmodule Sanbase.Email.MailjetApiBehaviour do
  @callback subscribe(atom(), String.t() | [String.t()]) :: :ok | {:error, term()}
  @callback unsubscribe(atom(), String.t() | [String.t()]) :: :ok | {:error, term()}
  @callback fetch_list_emails(atom()) :: {:ok, [String.t()]} | {:error, term()}
  @callback send_campaign(atom(), String.t(), keyword()) :: :ok | {:error, term()}
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
  @metric_updates_list_id 10_327_883
  @dev_metric_updates_list_id 10_326_671
  @stage_metric_updates_list_id 10_326_676
  @new_registrations_list_id 10_327_896

  @mailjet_lists %{
    bi_weekly: @bi_weekly_list_id,
    monthly_newsletter: @monthly_newsletter_list_id,
    sanr_network_emails: @mailjet_sanr_list_id,
    alpha_naratives_emails: @alpha_naratives_list_id,
    metric_updates: @metric_updates_list_id,
    metric_updates_dev: @dev_metric_updates_list_id,
    metric_updates_stage: @stage_metric_updates_list_id,
    new_registrations: @new_registrations_list_id
  }

  def client do
    Application.get_env(:sanbase, :mailjet_api, __MODULE__)
  end

  @doc """
  Creates and sends a campaign to a specified contact list.

  ## Parameters

  * `list_atom` - The atom representing the contact list to send to
  * `html_content` - The HTML content of the email
  * `opts` - Additional options for the campaign
    * `:title` - The title of the campaign (default: "Metric Updates")
    * `:subject` - The subject line of the email (default: "Metric Updates")
    * `:sender_email` - The sender email address (default: "metrics@santiment.net")
    * `:sender_name` - The sender name (default: "Santiment Metrics")
    * `:locale` - The locale for the campaign (default: "en_US")
    * `:text_content` - The plain text content of the email (default: "")

  ## Returns

  * `:ok` - If the campaign was successfully created and sent
  * `{:error, reason}` - If there was an error at any step

  ## Example

  ```elixir
  html_content = \"\"\"
  <h2>New Metrics Available</h2>
  <p>We've added the following metrics:</p>
  <ul>
    <li>Price/Volume Correlation</li>
    <li>Exchange Inflow</li>
  </ul>
  <p><a href=\\"[[UNSUB_LINK_EN]]\\">Unsubscribe</a></p>
  \"\"\"

  Sanbase.Email.MailjetApi.send_campaign(
    :metric_updates_dev,
    html_content,
    [
      title: "April Metrics Update",
      subject: "New Metrics Available - April 2025"
    ]
  )
  ```
  """
  @spec send_campaign(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def send_campaign(list_atom, html_content, opts \\ []) do
    campaign_url = @base_url <> "campaigndraft"
    list_id = @mailjet_lists[list_atom]

    # Default sender information can be overridden through opts
    title = Keyword.get(opts, :title, "Metric Updates")
    subject = Keyword.get(opts, :subject, "Metric Updates")
    sender_email = Keyword.get(opts, :sender_email, "support@santiment.net")
    sender_name = Keyword.get(opts, :sender_name, "Santiment Metrics")
    locale = Keyword.get(opts, :locale, "en_US")
    text_content = Keyword.get(opts, :text_content, "")

    # Create campaign draft
    draft_data = %{
      "Title" => title,
      "Subject" => subject,
      "SenderEmail" => sender_email,
      "Sender" => sender_name,
      "ContactsListID" => list_id,
      "Locale" => locale
    }

    result =
      with {:ok, %{body: %{"Data" => data}}} <- make_request(:post, campaign_url, draft_data),
           draft_id when is_integer(draft_id) <- get_draft_id(data),

           # Calculate URLs and prepare content data
           content_url = "#{campaign_url}/#{draft_id}/detailcontent",
           content_data = %{
             "Headers" => "object",
             "Html-part" => html_content,
             "Text-part" => text_content
           },
           {:ok, _content_response} <- make_request(:post, content_url, content_data),

           # Send the campaign
           send_url = "#{campaign_url}/#{draft_id}/send",
           {:ok, _send_response} <- make_request(:post, send_url, %{}) do
        Logger.info("Campaign successfully created and sent to list #{list_atom}")
        :ok
      else
        {:draft_id_error, reason} ->
          Logger.error("Failed to extract draft ID: #{inspect(reason)}")
          {:error, reason}

        {:ok, response} ->
          Logger.error("Unexpected response format from Mailjet API: #{inspect(response)}")
          {:error, {:unexpected_format, response}}

        {:error, response} ->
          Logger.error(
            "Failed to create/send campaign to list #{list_atom}: #{inspect(response)}"
          )

          {:error, response}
      end

    # Log the complete result for debugging
    Logger.debug("Campaign operation result: #{inspect(result)}")

    result
  end

  # Helper function to extract draft ID from response
  defp get_draft_id(data) when is_list(data) and length(data) > 0 do
    case Enum.at(data, 0) do
      %{"ID" => id} when is_integer(id) ->
        id

      other ->
        Logger.error("Could not find ID in draft data: #{inspect(other)}")
        {:draft_id_error, {:invalid_draft_data, other}}
    end
  end

  defp get_draft_id(data) do
    Logger.error("Invalid draft data structure: #{inspect(data)}")
    {:draft_id_error, {:invalid_data_structure, data}}
  end

  # Helper function to make HTTP requests to Mailjet API
  defp make_request(method, url, data) do
    Logger.debug("Making #{method} request to #{url} with data: #{inspect(data)}")

    try do
      result = apply(Req, method, [url, [json: data, headers: headers()]]) |> dbg()

      case result do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          Logger.debug("Successful response from #{url}: #{inspect(body)}")
          {:ok, %{status: status, body: body}}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Error response from #{url}: Status #{status}, Body: #{inspect(body)}")
          {:error, {:unexpected_format, body}}

        {:error, response} ->
          Logger.error("Error response from #{url}: #{inspect(response)}")
          {:error, response}
      end
    rescue
      error ->
        Logger.error("Error making request to Mailjet API #{url}: #{inspect(error)}")
        {:error, error}
    end
  end

  def subscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :subscribe)
  end

  def unsubscribe(list_atom, email_or_emails) do
    subscribe_unsubscribe(list_atom, email_or_emails, :unsubscribe)
  end

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
