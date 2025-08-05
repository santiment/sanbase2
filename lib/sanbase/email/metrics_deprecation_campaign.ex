defmodule Sanbase.Email.MetricsDeprecationCampaign do
  @moduledoc """
  Module for handling metrics deprecation campaign emails.

  ## Usage

  # Fill test list
  {:ok, _} = Sanbase.Email.MetricsDeprecationCampaign.build_mailjet_list()

  # Send to test list
  :ok = Sanbase.Email.MetricsDeprecationCampaign.send_simple_initial_campaign(10328703)

  # Fill production list
  {:ok, _} = Sanbase.Email.MetricsDeprecationCampaign.build_mailjet_list(testing: false)

  # Send to production list
  :ok = Sanbase.Email.MetricsDeprecationCampaign.send_simple_initial_campaign(10328716)
  """

  require Logger
  import Ecto.Query

  alias Sanbase.Billing.Subscription
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @deprecation_date "October 5th, 2025"
  @test_active_api_users_list_id 10_328_703
  @active_api_users_list_id 10_328_716

  @sanapi_product_id 1
  @base_url "https://api.mailjet.com/v3/REST/"
  @initial_campaign_name "Metrics Deprecation"
  @initial_campaign_subject "Important: Upcoming Changes to Our Metric Offerings – Action Required in 8 Weeks"

  @reminder_campaign_name "Metrics Deprecation Reminder"
  @reminder_campaign_subject "Reminder: Metric Changes in 4 Weeks – Action Required"

  @done_campaign_name "Metrics Deprecation Done"
  @done_campaign_subject "Metrics Deprecation Complete – Thank You"

  @initial_template """
  Dear [[data:username]],

  We are writing to inform you about an important strategic enhancement to our data platform aimed at providing you with the **most reliable, stable, and high-quality core metrics** in the crypto space. To achieve this, we are refining our focus by deprecating certain pre-computed derivative metrics. This change will ultimately empower you with greater flexibility and control over your data analysis and ML models.

  **What's Changing?** After **2 MONTHS**, we will be discontinuing the provision of the following derivative metrics via our API:

  ```
  "social_dominance_4chan_1h_moving_average"
  "social_dominance_4chan_24h_moving_average"
  "social_dominance_ai_total_1h_moving_average"
  "social_dominance_ai_total_24h_moving_average"
  "social_dominance_bitcointalk_1h_moving_average"
  "social_dominance_bitcointalk_24h_moving_average"
  "social_dominance_farcaster_1h_moving_average"
  "social_dominance_farcaster_24h_moving_average"
  "social_dominance_reddit_1h_moving_average"
  "social_dominance_reddit_24h_moving_average"
  "social_dominance_telegram_1h_moving_average"
  "social_dominance_telegram_24h_moving_average"
  "social_dominance_total_1h_moving_average"
  "social_dominance_total_1h_moving_average_change_1d"
  "social_dominance_total_1h_moving_average_change_30d"
  "social_dominance_total_1h_moving_average_change_7d"
  "social_dominance_total_change_1d"
  "social_dominance_total_change_30d"
  "social_dominance_total_change_7d"
  "social_dominance_total_24h_moving_average"
  "social_dominance_total_24h_moving_average_change_1d"
  "social_dominance_total_24h_moving_average_change_30d"
  "social_dominance_total_24h_moving_average_change_7d"
  "social_dominance_twitter_1h_moving_average"
  "social_dominance_twitter_24h_moving_average"
  "social_dominance_youtube_videos_1h_moving_average"
  "social_dominance_youtube_videos_24h_moving_average"
  ```

  **Your raw, 5-minute granular data (e.g.,** social_dominance_total**, etc.) will remain fully available and will be our core focus moving forward.**

  **Why are we making this change?**

  - **Enhanced Data Quality:** By concentrating on our core metrics, we can dedicate more resources to ensuring their accuracy, consistency, and uptime, which are foundational to your success.
  - **Increased Flexibility:** You will gain the ability to compute custom derivatives tailored precisely to your unique ML models and analytical needs, removing any limitations from our pre-defined aggregations.
  - **What Action is Required?** You will need to **update your data pipelines and ML models** to compute these derivative metrics directly from our raw 5-minute data. **The deadline for this transition is #{@deprecation_date}**. Any calls to the deprecated API endpoints after this date will cease to function.

  **We are here to help you every step of the way:** We have prepared a **comprehensive "Migration Kit"** to make this transition as smooth as possible, which includes ready-to-use functions in Python (Pandas, NumPy) and R to replicate common derivative metric logic.

  **Access the Migration Kit and Support:** https://github.com/santiment/san-sdk/blob/master/building_derivative_metrics.md

  We understand this change requires effort on your part, and we are committed to providing robust support to ensure a seamless transition. Don’t hesitate to contact us in case you need some help and assistance with the process.

  Thank you for your continued partnership as we enhance our platform to deliver even higher quality data.

  Sincerely,

  Santiment Team.

  ---

  If you no longer wish to receive these emails, you can [unsubscribe here]([[UNSUB_LINK_EN]]).
  """

  @reminder_template """
  TBD
  ---

  If you no longer wish to receive these emails, you can [unsubscribe here]([[UNSUB_LINK_EN]]).
  """

  @done_template """
  TBD
  ---

  If you no longer wish to receive these emails, you can [unsubscribe here]([[UNSUB_LINK_EN]]).
  """

  @test_user_ids [1, 2]

  @doc """
  Gets all users with active SANAPI subscriptions.
  For testing, returns only users with ids in @test_user_ids (1, 2).
  """
  def get_active_sanapi_users(testing \\ true) do
    query =
      if testing do
        from(u in User,
          where: u.id in ^@test_user_ids,
          select: %{
            id: u.id,
            name: u.name,
            username: u.username,
            email: u.email
          }
        )
      else
        from(s in Subscription,
          join: p in assoc(s, :plan),
          join: u in assoc(s, :user),
          where:
            p.product_id == ^@sanapi_product_id and
              s.status in ["active", "past_due"],
          select: %{
            id: u.id,
            name: u.name,
            username: u.username,
            email: u.email
          }
        )
      end

    Repo.all(query)
  end

  @doc """
  Creates a new contact list in Mailjet with the given name.
  Returns the list ID if successful.
  """
  def create_mailjet_list(list_name) do
    url = @base_url <> "contactslist"

    data = %{
      "Name" => list_name
    }

    case make_mailjet_request(:post, url, data) do
      {:ok, %{body: %{"Data" => [%{"ID" => list_id} | _]}}} ->
        Logger.info("Successfully created Mailjet list '#{list_name}' with ID #{list_id}")
        {:ok, list_id}

      {:ok, response} ->
        Logger.error("Unexpected response when creating list: #{inspect(response)}")
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        Logger.error("Failed to create Mailjet list '#{list_name}': #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Adds emails to a Mailjet list by list ID.
  """
  def add_emails_to_list(list_id, emails) when is_list(emails) do
    url = @base_url <> "contactslist/#{list_id}/managemanycontacts"

    contacts = Enum.map(emails, fn email -> %{"Email" => email} end)

    data = %{
      "Contacts" => contacts,
      "Action" => "addnoforce"
    }

    case make_mailjet_request(:post, url, data) do
      {:ok, _response} ->
        Logger.info("Successfully added #{length(emails)} emails to list #{list_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to add emails to list #{list_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Creates a contact property in Mailjet if it doesn't exist.
  """
  def create_contact_property(property_name, property_type \\ "str") do
    url = @base_url <> "contactmetadata"

    data = %{
      "Datatype" => property_type,
      "Name" => property_name,
      "NameSpace" => "static"
    }

    case make_mailjet_request(:post, url, data) do
      {:ok, _response} ->
        Logger.info("Successfully created contact property: #{property_name}")
        :ok

      {:error, %{"ErrorCode" => "mj-0010"}} ->
        # Property already exists
        Logger.info("Contact property #{property_name} already exists")
        :ok

      {:error, {:http_error, 400, %{"ErrorMessage" => "CM01 Property \"" <> _}}} ->
        # Property already exists (different error format)
        Logger.info("Contact property #{property_name} already exists")
        :ok

      {:error, reason} ->
        Logger.error("Failed to create contact property #{property_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Adds users with contact properties to a Mailjet list by list ID.
  Includes personalization data for each contact.
  """
  def add_users_to_list_with_properties(list_id, users) when is_list(users) do
    url = @base_url <> "contactslist/#{list_id}/managemanycontacts"

    contacts =
      Enum.map(users, fn user ->
        username = get_username_for_user(user)

        %{
          "Email" => user.email,
          "Properties" => %{
            "username" => username
          }
        }
      end)

    data = %{
      "Contacts" => contacts,
      "Action" => "addnoforce"
    }

    case make_mailjet_request(:post, url, data) do
      {:ok, _response} ->
        Logger.info(
          "Successfully added #{length(users)} users with properties to list #{list_id}"
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to add users with properties to list #{list_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Converts markdown content to HTML using Earmark.
  """
  def markdown_to_html(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _} ->
        {:ok, html}

      {:error, _html, errors} ->
        Logger.error("Failed to convert markdown to HTML: #{inspect(errors)}")
        {:error, {:markdown_conversion_failed, errors}}

      _ ->
        {:error, :unknown_markdown_error}
    end
  end

  def markdown_to_html(_), do: {:error, :invalid_markdown}

  @doc """
  **PASS 1: Build the Mailjet list with active SANAPI users**

  ## Options:
  - `:testing` - If true, only includes test user IDs 1, 2 (default: true)
  - `:create_new_list` - If true, creates a new list instead of using existing one (default: false)
  - `:list_name` - Name for the new list if creating one (default: "Metrics Deprecation - {timestamp}")

  ## Returns:
  - `{:ok, list_id}` - Successfully created/used list with users added
  - `{:error, reason}` - Failed to build list
  """
  def build_mailjet_list(opts \\ []) do
    testing = Keyword.get(opts, :testing, true)
    create_new_list = Keyword.get(opts, :create_new_list, false)

    list_name =
      Keyword.get(
        opts,
        :list_name,
        "Metrics Deprecation - #{DateTime.utc_now() |> DateTime.to_iso8601()}"
      )

    with {:ok, users} <- get_users(testing),
         {:ok, list_id} <- get_or_create_list(testing, create_new_list, list_name),
         :ok <- create_contact_property("username"),
         :ok <- add_users_to_list(users, list_id) do
      Logger.info("Successfully built Mailjet list #{list_id} with #{length(users)} users")
      {:ok, list_id}
    else
      {:error, reason} ->
        Logger.error("Failed to build Mailjet list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  **SIMPLE: Send campaign to whole list without personalization**

  Sends one campaign to the entire list with "Dear Customer" instead of personalized usernames.
  Much simpler - no temporary lists, no individual campaigns, just one campaign to the whole list.
  """
  def send_simple_initial_campaign(list_id) do
    simple_template = String.replace(@initial_template, "{{username}}", "Customer")

    with {:ok, html_content} <- markdown_to_html(simple_template),
         :ok <-
           send_campaign_to_list(
             list_id,
             html_content,
             @initial_campaign_name,
             @initial_campaign_subject
           ) do
      Logger.info("✅ Successfully sent simple initial campaign to list #{list_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("❌ Failed to send simple initial campaign: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  **SIMPLE: Send reminder campaign to whole list without personalization**
  """
  def send_simple_reminder_campaign(list_id) do
    simple_template = String.replace(@reminder_template, "{{username}}", "Customer")

    with {:ok, html_content} <- markdown_to_html(simple_template),
         :ok <-
           send_campaign_to_list(
             list_id,
             html_content,
             @reminder_campaign_name,
             @reminder_campaign_subject
           ) do
      Logger.info("✅ Successfully sent simple reminder campaign to list #{list_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("❌ Failed to send simple reminder campaign: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  **SIMPLE: Send done campaign to whole list without personalization**
  """
  def send_simple_done_campaign(list_id) do
    simple_template = String.replace(@done_template, "{{username}}", "Customer")

    with {:ok, html_content} <- markdown_to_html(simple_template),
         :ok <-
           send_campaign_to_list(
             list_id,
             html_content,
             @done_campaign_name,
             @done_campaign_subject
           ) do
      Logger.info("✅ Successfully sent simple done campaign to list #{list_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("❌ Failed to send simple done campaign: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp get_users(testing) do
    users = get_active_sanapi_users(testing)

    case users do
      [] ->
        {:error, :no_users_found}

      users ->
        Logger.info("Found #{length(users)} active SANAPI users")
        {:ok, users}
    end
  end

  defp get_or_create_list(testing, create_new_list, list_name) do
    if create_new_list do
      create_mailjet_list(list_name)
    else
      if testing do
        {:ok, @test_active_api_users_list_id}
      else
        {:ok, @active_api_users_list_id}
      end
    end
  end

  defp add_users_to_list(users, list_id) do
    valid_users = Enum.reject(users, fn user -> is_nil(user.email) end)

    case valid_users do
      [] ->
        {:error, :no_valid_emails}

      users ->
        add_users_to_list_with_properties(list_id, users)
    end
  end

  defp send_campaign_to_list(list_id, html_content, campaign_name, subject) do
    campaign_url = @base_url <> "campaigndraft"

    # Create campaign draft
    draft_data = %{
      "Title" => campaign_name,
      "Subject" => subject,
      "SenderEmail" => "support@santiment.net",
      "SenderName" => "Santiment Metrics",
      "ContactsListID" => list_id,
      "Locale" => "en_US"
    }

    with true <- has_mailjet_params?(),
         {:ok, %{body: %{"Data" => data}}} <-
           make_mailjet_request(:post, campaign_url, draft_data),
         draft_id when is_integer(draft_id) <- get_draft_id(data),

         # Calculate URLs and prepare content data
         content_url = "#{campaign_url}/#{draft_id}/detailcontent",
         content_data = %{
           "Headers" => "object",
           "Html-part" => html_content,
           "Text-part" => ""
         },
         {:ok, _content_response} <- make_mailjet_request(:post, content_url, content_data),

         # Send the campaign
         send_url = "#{campaign_url}/#{draft_id}/send",
         {:ok, _send_response} <- make_mailjet_request(:post, send_url, %{}) do
      Logger.debug("Campaign successfully created and sent to list #{list_id}")
      :ok
    else
      {:draft_id_error, reason} ->
        Logger.error("Failed to extract draft ID: #{inspect(reason)}")
        {:error, reason}

      {:ok, response} ->
        Logger.error("Unexpected response format from Mailjet API: #{inspect(response)}")
        {:error, {:unexpected_format, response}}

      {:error, response} ->
        Logger.error("Failed to create/send campaign to list #{list_id}: #{inspect(response)}")
        {:error, response}
    end
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

  defp has_mailjet_params?() do
    require Sanbase.Utils.Config, as: Config

    has? =
      not is_nil(Config.module_get(Sanbase.TemplateMailer, :api_key)) and
        not is_nil(Config.module_get(Sanbase.TemplateMailer, :secret))

    if has? do
      true
    else
      {:error, "Missing Mailjet API key and/or secret"}
    end
  end

  defp get_username_for_user(%{name: name, username: username, email: email}) do
    cond do
      not is_nil(name) and String.trim(name) != "" -> name
      not is_nil(username) and String.trim(username) != "" -> username
      not is_nil(email) and String.trim(email) != "" -> email
      true -> "Customer"
    end
  end

  defp make_mailjet_request(method, url, data) do
    Logger.debug("Making #{method} request to #{url} with data: #{inspect(data)}")

    try do
      result = apply(Req, method, [url, [json: data, headers: mailjet_headers()]])

      case result do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          Logger.debug("Successful response from #{url}: #{inspect(body)}")
          {:ok, %{status: status, body: body}}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Error response from #{url}: Status #{status}, Body: #{inspect(body)}")
          {:error, {:http_error, status, body}}

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

  defp mailjet_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Basic #{mailjet_basic_auth()}"}
    ]
  end

  defp mailjet_basic_auth do
    require Sanbase.Utils.Config, as: Config

    Base.encode64(
      Config.module_get!(Sanbase.TemplateMailer, :api_key) <>
        ":" <> Config.module_get!(Sanbase.TemplateMailer, :secret)
    )
  end
end
