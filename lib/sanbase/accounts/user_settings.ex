defmodule Sanbase.Accounts.UserSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.{User, Settings}
  alias Sanbase.Repo
  alias Sanbase.Billing.{Subscription, Product}

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

  def settings_for(%User{user_settings: %{settings: %Settings{}}} = user, opts) do
    user =
      case Keyword.get(opts, :force, false) do
        false -> user
        true -> Repo.preload(user, [:user_settings], force: true)
      end

    user.user_settings
    |> modify_settings()
  end

  def settings_for(%User{id: user_id}, _opts) do
    user_settings =
      Repo.get_by(__MODULE__, user_id: user_id)
      |> case do
        nil ->
          changeset(%__MODULE__{}, %{user_id: user_id, settings: %{}})
          |> Repo.insert!()

        %__MODULE__{} = us ->
          us
      end

    user_settings |> modify_settings()
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
    notifications_sent_today = Map.get(alerts_fired, Date.utc_today() |> to_string(), %{})

    default_alerts_limit_per_day = Settings.default_alerts_limit_per_day()

    result =
      Map.keys(default_alerts_limit_per_day)
      |> Enum.reduce(%{}, fn channel, map ->
        channel_limit =
          (Map.get(alerts_per_day_limit, channel) ||
             Map.fetch!(default_alerts_limit_per_day, channel))
          |> Sanbase.Math.to_integer()

        channel_sent_today =
          Map.get(notifications_sent_today, channel, 0)
          |> Sanbase.Math.to_integer()

        left_to_send = Enum.max([channel_limit - channel_sent_today, 0])

        Map.put(map, channel, left_to_send)
      end)

    {:ok, result}
  end

  def update_settings(user, %{is_subscribed_biweekly_report: true} = params) do
    case Subscription.current_subscription_plan(user.id, Product.product_sanbase()) do
      pro when pro in ["PRO", "PRO_PLUS"] -> settings_update(user.id, params)
      _ -> {:error, "Only PRO users can subscribe to Biweekly Report"}
    end
  end

  # max emails per day = 200, max telegram per day = 1000
  def update_settings(user, %{
        alerts_per_day_limit: %{"email" => email_limit, "telegram" => telegram_limit}
      })
      when is_integer(email_limit) and email_limit > 0 and is_integer(telegram_limit) and
             telegram_limit > 0 do
    default_limits = Sanbase.Accounts.Settings.default_alerts_limit_per_day()

    cond do
      email_limit > 200 ->
        {:error, "Email limit cannot be more than 200"}

      telegram_limit > 1000 ->
        {:error, "Telegram limit cannot be more than 1000"}

      true ->
        limits =
          default_limits |> Map.merge(%{"email" => email_limit, "telegram" => telegram_limit})

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
      Repo.get_by(__MODULE__, user_id: user_id)
      |> case do
        nil ->
          # There are no settings inserted for that user still, create a record
          changeset(%__MODULE__{}, %{user_id: user_id, settings: params})

        %__MODULE__{} = us ->
          changeset(us, %{settings: params})
      end

    case changeset |> Repo.insert_or_update() do
      {:ok, %__MODULE__{} = us} ->
        maybe_emit_event_on_changes(user_id, changeset.changes)
        {:ok, %{us | settings: modify_settings(us)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_emit_event_on_changes(user_id, %{settings: settings}) do
    settings_changes = settings.changes
    email_lists_keys = [:is_subscribed_biweekly_report, :is_subscribed_monthly_newsletter]

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
      us.settings.alerts_per_day_limit
      |> case do
        empty_map when map_size(empty_map) == 0 ->
          Sanbase.Accounts.Settings.default_alerts_limit_per_day()

        map when is_map(map) ->
          map
      end

    us.settings
    |> Map.put(:has_telegram_connected, us.settings.telegram_chat_id != nil)
    |> Map.put(:alerts_per_day_limit, alerts_per_day_limit)
  end
end
