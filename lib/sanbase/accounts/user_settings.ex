defmodule Sanbase.Accounts.UserSettings do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Accounts.Settings
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo

  @self_reset_api_rate_limits_cooldown 90

  schema "user_settings" do
    belongs_to(:user, User)
    embeds_one(:settings, Settings, on_replace: :update)

    timestamps()
  end

  def changeset(%__MODULE__{} = user_settings, attrs \\ %{}) do
    user_settings
    |> cast(attrs, [:user_id])
    |> cast_embed(:settings, required: true, with: &Settings.changeset/2)
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  def settings_for(user, opts \\ [])

  def settings_for(user, opts) do
    user
    |> user_settings_for(opts)
    |> modify_settings()
  end

  @doc ~s"""
  Returns a boolean whether or not the user can self-reset their API calls limits.
  The rate limits can be reset by the user once every #{@self_reset_api_rate_limits_cooldown} days.
  Giving the ability of users to self reset their rate limits once in a while can help them resolve
  the issue much quicker, instead of waiting for Santiment support.
  Rate limits might need resetting due to development bugs, or the user just needing to upgrade to a
  higher plan. Both things might take some to fix/upgrade, so having the option to unblock yourself
  until the issues are resolved is required.k
  """
  def can_self_reset_api_rate_limits?(user) do
    %{self_api_rate_limits_reset_at: last_self_reset_at} = settings_for(user)

    if do_can_self_reset_api_rate_limits?(last_self_reset_at) do
      true
    else
      {:error,
       """
       Cannot self reset the API calls rate limits.
       The last reset was less than #{@self_reset_api_rate_limits_cooldown} days ago on #{last_self_reset_at}.
       """}
    end
  end

  def disconnect_telegram_bot(user) do
    # First get the existing chat id so we can send it with the event
    # so the user events subscriber can send a message to that chat id
    # informing that the bot is disconnected.
    user_settings =
      %{settings: %{telegram_chat_id: telegram_chat_id}} =
      user_settings_for(user, force: true)

    user_settings
    |> changeset(%{settings: %{telegram_chat_id: nil, alert_notify_telegram: false}})
    |> Sanbase.Repo.update()
    |> case do
      {:ok, user_settings} ->
        Sanbase.Accounts.EventEmitter.emit_event(
          {:ok, user},
          :disconnect_telegram_bot,
          %{telegram_chat_id: telegram_chat_id}
        )

        {:ok, user_settings}

      {:error, error} ->
        {:error, error}
    end
  end

  def update_self_reset_api_rate_limits_datetime(user, dt) do
    user
    |> user_settings_for(force: true)
    |> changeset(%{user_id: user.id, settings: %{self_api_rate_limits_reset_at: dt}})
    |> Sanbase.Repo.update()
  end

  @spec max_alerts_to_send(%User{}) :: {:ok, %{required(channel) => count}}
        when channel: String.t(), count: non_neg_integer()
  def max_alerts_to_send(%User{} = user) do
    # Force the settings to be fetched and not taken from the user struct
    # This is done so while evaluating alerts, the alerts fired count is
    # properly reflected here.
    user_settings = Sanbase.Accounts.UserSettings.settings_for(user, force: true)

    %{
      alerts_fired: alerts_fired,
      alerts_per_day_limit: alerts_per_day_limit
    } = user_settings

    # A map of "channel" => list pairs
    notifications_sent_today = Map.get(alerts_fired, to_string(Date.utc_today()), %{})

    default_alerts_limit_per_day = Settings.default_alerts_limit_per_day()

    result =
      default_alerts_limit_per_day
      |> Map.keys()
      |> Enum.reduce(%{}, fn channel, map ->
        channel_limit =
          Sanbase.Math.to_integer(
            Map.get(alerts_per_day_limit, channel) || Map.fetch!(default_alerts_limit_per_day, channel)
          )

        channel_sent_today =
          notifications_sent_today
          |> Map.get(channel, 0)
          |> Sanbase.Math.to_integer()

        left_to_send = Enum.max([channel_limit - channel_sent_today, 0])

        Map.put(map, channel, left_to_send)
      end)

    {:ok, result}
  end

  def update_settings(user, %{is_subscribed_biweekly_report: true} = params) do
    case Subscription.current_subscription_plan(user.id, Product.product_sanbase()) do
      pro when pro in ["PRO", "PRO_PLUS", "MAX"] -> settings_update(user.id, params)
      _ -> {:error, "Only PRO users can subscribe to Biweekly Report"}
    end
  end

  # max emails per day = 200, max telegram per day = 1000
  def update_settings(user, %{alerts_per_day_limit: %{"email" => email_limit, "telegram" => telegram_limit}})
      when is_integer(email_limit) and email_limit > 0 and is_integer(telegram_limit) and telegram_limit > 0 do
    default_limits = Sanbase.Accounts.Settings.default_alerts_limit_per_day()

    cond do
      email_limit > 200 ->
        {:error, "Email limit cannot be more than 200"}

      telegram_limit > 1000 ->
        {:error, "Telegram limit cannot be more than 1000"}

      true ->
        limits = Map.merge(default_limits, %{"email" => email_limit, "telegram" => telegram_limit})

        settings_update(user.id, %{alerts_per_day_limit: limits})
    end
  end

  def update_settings(_, %{alerts_per_day_limit: _}) do
    {:error, "Invalid values for alerts_per_day_limit"}
  end

  def update_settings(%User{id: id}, params) do
    settings_update(id, params)
  end

  def toggle_is_promoter(%User{id: user_id}, params) do
    settings_update(user_id, params)
  end

  def toggle_notification_channel(%User{id: user_id}, params) do
    settings_update(user_id, params)
  end

  def set_telegram_chat_id(user_id, chat_id) do
    settings_update(user_id, %{telegram_chat_id: chat_id})
  end

  defp settings_update(user_id, params) do
    changeset =
      __MODULE__
      |> Repo.get_by(user_id: user_id)
      |> case do
        nil ->
          # There are no settings inserted for that user still, create a record
          changeset(%__MODULE__{}, %{user_id: user_id, settings: params})

        %__MODULE__{} = us ->
          changeset(us, %{settings: params})
      end

    case Repo.insert_or_update(changeset) do
      {:ok, %__MODULE__{} = us} ->
        maybe_emit_event_on_changes(user_id, changeset.changes)
        {:ok, %{us | settings: modify_settings(us)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_emit_event_on_changes(user_id, %{settings: settings}) do
    settings_changes = settings.changes

    email_lists_keys = [
      :is_subscribed_biweekly_report,
      :is_subscribed_monthly_newsletter,
      :is_subscribed_metric_updates
    ]

    for key <- Map.keys(settings_changes) do
      if key in email_lists_keys do
        Sanbase.Email.MailjetEventEmitter.emit_event(
          {:ok, user_id},
          key,
          Map.put(%{}, key, settings_changes[key])
        )
      end
    end
  end

  defp maybe_emit_event_on_changes(_user_id, _), do: :ok

  defp modify_settings(%__MODULE__{} = us) do
    # The default value of the alerts limit is an empty map.
    # Put the defaults here, after fetching from the DB, at runtime.
    # This is done so the default values can be changed without altering DB records.
    alerts_per_day_limit =
      case us.settings.alerts_per_day_limit do
        empty_map when map_size(empty_map) == 0 ->
          Sanbase.Accounts.Settings.default_alerts_limit_per_day()

        map when is_map(map) ->
          map
      end

    can_self_reset_limits? =
      do_can_self_reset_api_rate_limits?(us.settings.self_api_rate_limits_reset_at)

    can_self_reset_limits_at =
      next_self_reset_api_calls_rate_limits_dt(us.settings.self_api_rate_limits_reset_at)

    us.settings
    |> Map.put(:has_telegram_connected, us.settings.telegram_chat_id != nil)
    |> Map.put(:alerts_per_day_limit, alerts_per_day_limit)
    |> Map.put(:can_self_reset_api_rate_limits, can_self_reset_limits?)
    |> Map.put(:can_self_reset_api_rate_limits_at, can_self_reset_limits_at)
  end

  defp user_settings_for(%{user_settings: %{settings: _}} = user, opts) do
    user =
      if Keyword.get(opts, :force, false) do
        Repo.preload(user, [:user_settings], force: true)
      else
        user
      end

    user.user_settings
  end

  defp user_settings_for(%User{id: user_id}, _opts) do
    case Repo.get_by(__MODULE__, user_id: user_id) do
      nil ->
        %__MODULE__{}
        |> changeset(%{user_id: user_id, settings: %{}})
        |> Repo.insert!()

      %__MODULE__{} = us ->
        us
    end
  end

  defp do_can_self_reset_api_rate_limits?(nil = _last_self_reset_at), do: true

  defp do_can_self_reset_api_rate_limits?(%DateTime{} = last_self_reset_at) do
    dt_threshold = DateTime.add(DateTime.utc_now(), -@self_reset_api_rate_limits_cooldown, :day)

    DateTime.compare(last_self_reset_at, dt_threshold) != :gt
  end

  defp next_self_reset_api_calls_rate_limits_dt(nil), do: DateTime.utc_now()

  defp next_self_reset_api_calls_rate_limits_dt(%DateTime{} = last_self_reset_at) do
    DateTime.add(last_self_reset_at, @self_reset_api_rate_limits_cooldown, :day)
  end
end
