defmodule Sanbase.Email.Mailchimp do
  require Sanbase.Utils.Config, as: Config
  require Logger

  @base_url "https://us14.api.mailchimp.com/3.0"
  @weekly_digest_list_id "41325871aa"

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
    |> Enum.map(&Sanbase.Repo.get_by(Sanbase.Auth.User, email: &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(Sanbase.Auth.UserSettings.settings_for(&1).newsletter_subscription == :off))
    |> Enum.each(
      &Sanbase.Auth.UserSettings.change_newsletter_subscription(&1, %{
        newsletter_subscription: :off
      })
    )
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
      Sanbase.Auth.Settings.daily_subscription_type()
      |> Sanbase.Auth.Statistics.newsletter_subscribed_users()

    weekly =
      Sanbase.Auth.Settings.weekly_subscription_type()
      |> Sanbase.Auth.Statistics.newsletter_subscribed_users()

    Enum.concat(daily, weekly)
    |> Enum.map(& &1.email)
    |> Enum.uniq()
  end

  def subscribe_to_digest(body_json) do
    HTTPoison.post!(weekly_digest_members_url(), body_json, headers())
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
