defmodule Sanbase.Email.SubscriptionManager do
  @moduledoc """
  Module for managing email subscriptions between user settings and Mailjet.

  This module provides functions to:
  1. Fetch emails of users with active or trialing subscriptions
  2. Fetch emails of users who have opted in for metric updates
  3. Find mismatches between subscription status and user settings
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Email.MailjetApi

  @doc """
  Fetches all emails of users with active or trialing subscriptions for Sanbase product.

  Returns a list of email strings.
  """
  def fetch_emails_with_active_subscriptions do
    from(s in Subscription,
      join: p in assoc(s, :plan),
      join: u in User,
      on: s.user_id == u.id,
      where: s.status in ["active", "past_due", "trialing"],
      where: not is_nil(u.email),
      select: u.email
    )
    |> Repo.all()
    |> Enum.uniq()
  end

  @doc """
  Fetches all emails of users who have opted in for metric updates in their settings.

  Returns a list of email strings.
  """
  def fetch_emails_with_metric_updates_enabled do
    from(u in User,
      join: us in UserSettings,
      on: us.user_id == u.id,
      where: fragment("(?.settings->>'is_subscribed_metric_updates')::boolean = true", us),
      where: not is_nil(u.email),
      select: u.email
    )
    |> Repo.all()
    |> Enum.uniq()
  end

  @doc """
  Finds emails that have the metric updates flag enabled but don't have an active subscription.

  Returns a list of email strings.
  """
  def find_emails_with_flag_but_no_subscription do
    emails_with_flag = fetch_emails_with_metric_updates_enabled()
    emails_with_subscription = fetch_emails_with_active_subscriptions()

    emails_with_flag -- emails_with_subscription
  end

  @doc """
  Finds emails that have an active subscription but don't have the metric updates flag enabled.

  Returns a list of email strings.
  """
  def find_emails_with_subscription_but_no_flag do
    emails_with_flag = fetch_emails_with_metric_updates_enabled()
    emails_with_subscription = fetch_emails_with_active_subscriptions()

    emails_with_subscription -- emails_with_flag
  end

  @doc """
  Initializes the Mailjet metric updates list with all users who have active subscriptions.
  This is useful for bootstrapping the list or ensuring all active subscribers are included.

  Returns :ok on success or {:error, reason} on failure.
  """
  def initialize_mailjet_list_with_active_subscribers do
    # Get all emails with active subscriptions
    emails_with_subscription = fetch_emails_with_active_subscriptions()

    # Get current state from Mailjet
    with {:ok, mailjet_emails} <- MailjetApi.fetch_list_emails(:metric_updates) do
      # Emails to add (have subscription but not in Mailjet)
      emails_to_add = emails_with_subscription -- mailjet_emails

      # Process subscriptions in batches of 100
      emails_to_add
      |> Enum.chunk_every(50)
      |> Enum.each(fn batch ->
        MailjetApi.subscribe(:metric_updates, batch)
        # Add a small delay to avoid rate limiting
        Process.sleep(1000)
      end)

      {:ok, length(emails_to_add)}
    end
  end

  # unsubscribe all existing emails in the list
  def unsubscribe_all_existing_emails_in_list do
    with {:ok, mailjet_emails} <- MailjetApi.fetch_list_emails(:metric_updates) do
      # chunk the emails in batches of 100
      mailjet_emails
      |> Enum.chunk_every(50)
      |> Enum.each(fn batch ->
        MailjetApi.unsubscribe(:metric_updates, batch)
        # Add a small delay to avoid rate limiting
        Process.sleep(1000)
      end)

      :ok
    end
  end

  @doc """
  Synchronizes the Mailjet metric updates list with the current state of user settings and subscriptions.
  Processes subscriptions and unsubscriptions in batches of 100 to avoid overwhelming the API.

  Returns :ok on success or {:error, reason} on failure.
  """
  def sync_mailjet_metric_updates_list do
    # Get current state from Mailjet
    with {:ok, mailjet_emails} <- MailjetApi.fetch_list_emails(:metric_updates) do
      # Get emails that should be in the list (active subscription + flag enabled)
      emails_with_flag = fetch_emails_with_metric_updates_enabled()
      emails_with_subscription = fetch_emails_with_active_subscriptions()
      should_be_subscribed = emails_with_flag -- (emails_with_flag -- emails_with_subscription)

      # Emails to add (should be subscribed but not in Mailjet)
      emails_to_add = should_be_subscribed -- mailjet_emails

      # Emails to remove (in Mailjet but shouldn't be subscribed)
      emails_to_remove = mailjet_emails -- should_be_subscribed

      # Process subscriptions in batches of 100
      emails_to_add
      |> Enum.chunk_every(100)
      |> Enum.each(fn batch ->
        MailjetApi.subscribe(:metric_updates, batch)
        # Add a small delay to avoid rate limiting
        Process.sleep(100)
      end)

      # Process unsubscriptions in batches of 100
      emails_to_remove
      |> Enum.chunk_every(100)
      |> Enum.each(fn batch ->
        MailjetApi.unsubscribe(:metric_updates, batch)
        # Add a small delay to avoid rate limiting
        Process.sleep(100)
      end)

      :ok
    end
  end
end
