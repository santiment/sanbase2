defmodule Sanbase.Email.Lists do
  @moduledoc """
  Registry of the email lists that users can subscribe to.

  Every list follows the same standard:
    - one Mailjet list, one backend setting, at most one UI toggle
    - a legal basis: `:consent` (opt-in only, off by default),
      `:legitimate_interest` (on by default, easy opt-out) or `:service`
      (required to run the service, no toggle)
    - for consent lists, every change is recorded with its time and source
      (see `Sanbase.Email.ListConsent`)
    - withdrawal syncs both ways: turning the setting off removes the contact
      from Mailjet, and unsubscribing in Mailjet turns the setting off

  Lists are migrated to this registry one at a time. Lists that are not here yet
  are still wired by hand in `Sanbase.Email.MailjetEventEmitter`,
  `Sanbase.EventBus.UserEventsSubscriber` and `Sanbase.Email.MailjetEventHandler`.

  ## Fields

    - `:mailjet_list` - the list key used with `Sanbase.Email.MailjetApi`
    - `:setting` - the user settings key that the UI toggle shows
    - `:mirrored_settings` - legacy settings keys that hold the same value
    - `:user_field` - a `users` column that holds the same value
    - `:basis` - the legal basis for sending
    - `:default` - the setting value for users that have not chosen
    - `:entry_points` - where users can subscribe, used as consent sources
    - `:unsubscribed_by` - Mailjet list ids whose unsubscribe link withdraws
      the subscription (received through the Mailjet webhook)
  """

  @type list_key :: :newsletter
  @type basis :: :consent | :legitimate_interest | :service

  @lists %{
    # Santiment Weekly. Mailjet list "Newsletter List Cleaned Oct 2026"; the id
    # is set per environment with MAILJET_MARKETING_NEWSLETTER_LIST_ID
    # (10331431 in prod).
    #
    # Users see one consent in two places: the "Weekly newsletter" toggle in
    # Account Settings and the marketing checkbox at signup and on the
    # /privacy-policy page (users.marketing_accepted). All of them hold the same
    # value.
    newsletter: %{
      mailjet_list: :marketing_newsletter,
      setting: :is_subscribed_weekly_newsletter,
      mirrored_settings: [:is_subscribed_marketing_emails],
      user_field: :marketing_accepted,
      basis: :consent,
      default: false,
      entry_points: [:signup_dialog, :privacy_page, :settings_toggle, :website_form],
      unsubscribed_by: [
        # Newsletter List Cleaned Oct 2026
        "10331431",
        # SanR network emails
        "10321582",
        # Alpha Narratives emails
        "10321590"
      ]
    }
  }

  @doc "Returns all registered lists as a map of list key to list definition."
  @spec all() :: %{list_key() => map()}
  def all(), do: @lists

  @doc "Returns the definition of a registered list."
  @spec get!(list_key()) :: map()
  def get!(list_key), do: Map.fetch!(@lists, list_key)

  @doc "Returns every settings key that holds the subscription of the given list."
  @spec settings_keys(list_key()) :: [atom()]
  def settings_keys(list_key) do
    list = get!(list_key)
    [list.setting | list.mirrored_settings]
  end

  @doc """
  Returns `{:ok, list_key, value}` when the settings params change the
  subscription of a registered list, or `:error` otherwise.

  The list setting takes precedence over the mirrored settings.
  """
  @spec subscription_change(map()) :: {:ok, list_key(), boolean()} | :error
  def subscription_change(params) when is_map(params) do
    Enum.find_value(@lists, :error, fn {list_key, _list} ->
      list_key
      |> settings_keys()
      |> Enum.find_value(fn key ->
        case Map.fetch(params, key) do
          {:ok, value} when is_boolean(value) -> {:ok, list_key, value}
          _ -> nil
        end
      end)
    end)
  end

  @doc "Returns the params with the settings keys of every registered list removed."
  @spec drop_settings_keys(map()) :: map()
  def drop_settings_keys(params) when is_map(params) do
    keys = Enum.flat_map(Map.keys(@lists), &settings_keys/1)
    Map.drop(params, keys)
  end

  @doc "Returns the registered list whose subscription is withdrawn by the Mailjet list id."
  @spec list_unsubscribed_by(String.t() | integer()) :: {:ok, list_key()} | :error
  def list_unsubscribed_by(mailjet_list_id) do
    mailjet_list_id = to_string(mailjet_list_id)

    Enum.find_value(@lists, :error, fn {list_key, list} ->
      if mailjet_list_id in list.unsubscribed_by, do: {:ok, list_key}
    end)
  end
end
