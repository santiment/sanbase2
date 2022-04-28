defmodule Sanbase.Email.MailchimpApi do
  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Accounts.{User, UserSettings, Settings, Statistics}

  @base_url "https://us14.api.mailchimp.com/3.0"
  @weekly_digest_list_id "41325871aa"
  @bi_weekly_list_id "3e5b56534c"

  def account() do
    Mailchimp.Account.get!()
  end

  def all_lists do
    Mailchimp.Account.get_all_lists!() |> Enum.map(&Map.take(&1, [:id, :name]))
  end

  def list(account, list_id) do
    Mailchimp.Account.get_list!(account, list_id)
  end

  def members(list) do
    members(list, [], 0)
  end

  defp members(list, members, offset) do
    new_members =
      Mailchimp.List.members!(list, %{
        fields: "members.email_address,members.status",
        count: 1000,
        offset: offset
      })
      |> Enum.map(&Map.take(&1, [:email_address, :status]))

    case length(new_members) < 1000 do
      true -> members ++ new_members
      false -> members(list, members ++ new_members, offset + length(new_members))
    end
  end

  def batch_subscribe(list, emails) when is_list(emails) do
    members = emails |> Enum.map(fn email -> %{email_address: email, status: "subscribed"} end)
    Mailchimp.List.batch_subscribe!(list, members, %{update_existing: true})
  end

  def batch_unsubscribe(list, emails) when is_list(emails) do
    members = emails |> Enum.map(fn email -> %{email_address: email, status: "unsubscribed"} end)
    Mailchimp.List.batch_subscribe!(list, members, %{update_existing: true})
  end

  def sync() do
    for list_id <- lists do
      sync_list(list_id)
    end
  end

  def sync_list(list_id) do
    members = account() |> list(list_id) |> members()
    {subscribed_in_mailchimp, unsubscribed_from_mailchimp} = get_members_by_status()

    # if contact unsubscribes from email - update subscription status in Sanbase
    update_unsubscribed_in_sanbase(list_id, unsubscribed_from_mailchimp)

    newly_subscribed = subscribed_in_sanbase(list_id) -- subscribed_in_mailchimp
    newly_unsubscribed = unsubscribed_in_sanbase(list_id) -- unsubscribed_from_mailchimp
  end

  def run() do
    if mailchimp_api_key() do
      {subscribed_in_mailchimp, unsubscribed_from_mailchimp} = get_subscribed_unsubscribed()
      update_unsubscribed_locally(unsubscribed_from_mailchimp)
      newly_subscribed = subscribed_in_sanbase() -- subscribed_in_mailchimp
      add_newly_subscribed_in_mailchimp(newly_subscribed)
    else
      :ok
    end
  end

  def get_subscribed_unsubscribed() do
    all_members =
      HTTPoison.get!("#{weekly_digest_members_url()}?#{default_url_params()}", headers())
      |> Map.get(:body)
      |> Jason.decode!()
      |> Map.get("members")

    subscribed =
      Enum.filter(all_members, &(Map.get(&1, "status") == "subscribed"))
      |> Enum.map(&Map.get(&1, "email_address"))

    unsubscribed =
      Enum.filter(all_members, &(Map.get(&1, "status") != "subscribed"))
      |> Enum.map(&Map.get(&1, "email_address"))

    {subscribed, unsubscribed}
  end

  def update_unsubscribed_locally(unsubscribed) do
    unsubscribed
    |> Enum.map(&User.by_email(&1))
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(UserSettings.settings_for(&1).newsletter_subscription == :off))
    |> Enum.each(fn user ->
      Logger.info("Email unsubscribed in Mailchimp #{user.email}. Updating in Sanbase.")

      UserSettings.change_newsletter_subscription(user, %{
        newsletter_subscription: :off
      })
    end)
  end

  def add_newly_subscribed_in_mailchimp(newly_subscribed) do
    newly_subscribed
    |> Enum.each(&add_email_to_mailchimp/1)
  end

  def add_email_to_mailchimp(email) do
    %{
      email_address: email,
      status: "subscribed"
    }
    |> Jason.encode!()
    |> subscribe_to_digest()
  end

  def subscribed_in_sanbase() do
    daily =
      Settings.daily_subscription_type()
      |> Statistics.newsletter_subscribed_users()

    weekly =
      Settings.weekly_subscription_type()
      |> Statistics.newsletter_subscribed_users()

    Enum.concat(daily, weekly)
    |> Enum.map(& &1.email)
    |> Enum.uniq()
  end

  def subscribe_email(email) do
    body_json =
      %{
        email_address: email,
        status: "subscribed"
      }
      |> Jason.encode!()

    do_subscribe_unsubscribe(email, body_json, "subscribe")
  end

  def unsubscribe_email(email) do
    body_json =
      %{
        email_address: email,
        status: "unsubscribed"
      }
      |> Jason.encode!()

    do_subscribe_unsubscribe(email, body_json, "unsubscribe")
  end

  def do_subscribe_unsubscribe(email, body_json, type) do
    if mailchimp_api_key() do
      subscriber_hash = :crypto.hash(:md5, String.downcase(email)) |> Base.encode16(case: :lower)

      HTTPoison.patch(
        "#{@base_url}/lists/#{@weekly_digest_list_id}/members/#{subscriber_hash}",
        body_json,
        headers()
      )
      |> case do
        {:ok, %HTTPoison.Response{status_code: 200}} ->
          Logger.info("Email #{type} from Mailchimp: #{body_json}")
          :ok

        {:ok, %HTTPoison.Response{} = response} ->
          Logger.error(
            "Error #{type} email from Mailchimp: #{inspect(body_json)}}. Response: #{inspect(response)}"
          )

        {:error, reason} ->
          Logger.error(
            "Error #{type} email from Mailchimp : #{body_json}}. Reason: #{inspect(reason)}"
          )
      end
    else
      :ok
    end
  end

  def subscribe_to_digest(body_json) do
    HTTPoison.post(weekly_digest_members_url(), body_json, headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("Email added to Mailchimp: #{body_json}")
        :ok

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error adding email to Mailchimp: #{inspect(body_json)}}. Response: #{inspect(response)}"
        )

        {:error, response.body}

      {:error, reason} ->
        Logger.error(
          "Error adding email to Mailchimp : #{body_json}}. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp mailchimp_api_key() do
    Config.get(:api_key)
  end

  defp weekly_digest_members_url do
    "#{@base_url}/lists/#{@weekly_digest_list_id}/members"
  end

  defp default_url_params do
    "fields=members.email_address,members.status&count=1000"
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "apikey #{mailchimp_api_key()}"}
    ]
  end
end
