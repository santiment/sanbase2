defmodule Sanbase.Accounts.UserSettings do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Sanbase.Accounts.{User, Settings}
  alias Sanbase.Repo
  alias Sanbase.Billing
  alias Sanbase.Billing.Product

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
    user_settings_for(user, opts)
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
  def can_self_reset_api_rate_limits?(%Settings{
        self_api_rate_limits_reset_at: last_self_reset_at
      }) do
    case do_can_self_reset_api_rate_limits?(last_self_reset_at) do
      true ->
        true

      false ->
        {:error,
         """
         Cannot self reset the API calls rate limits.
         The last reset was less than #{@self_reset_api_rate_limits_cooldown} days ago on #{last_self_reset_at}.
         """}
    end
  end

  def can_self_reset_api_rate_limits_at(%Settings{
        self_api_rate_limits_reset_at: last_self_reset_at
      }) do
    case last_self_reset_at do
      nil ->
        {:ok, DateTime.utc_now()}

      %DateTime{} ->
        {:ok, DateTime.add(last_self_reset_at, @self_reset_api_rate_limits_cooldown, :day)}
    end
  end

  def next_self_reset_api_calls_rate_limits_dt(%DateTime{} = last_self_reset_at) do
    DateTime.add(last_self_reset_at, @self_reset_api_rate_limits_cooldown, :day)
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
    user_settings_for(user, force: true)
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

  @doc """
  Update the user settings.

  Changes to `is_subscribed_metric_updates` are treated as an explicit user choice
  and recorded in `metric_updates_opted_out_at`. Pass `explicit: false` for
  changes made by the system (e.g. billing) so they are not recorded as such.
  """
  def update_settings(user, params, opts \\ []) do
    params = track_metric_updates_opt_out(params, opts)

    case params do
      %{is_subscribed_biweekly_report: true} ->
        if can_subscribe_biweekly_report?(user) do
          do_update_settings(user, params)
        else
          {:error, "Only users with an active subscription plan can subscribe to Biweekly Report"}
        end

      _ ->
        do_update_settings(user, params)
    end
  end

  defp track_metric_updates_opt_out(params, opts) do
    case {Keyword.get(opts, :explicit, true), Map.fetch(params, :is_subscribed_metric_updates)} do
      {true, {:ok, false}} ->
        Map.put(
          params,
          :metric_updates_opted_out_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      {true, {:ok, true}} ->
        Map.put(params, :metric_updates_opted_out_at, nil)

      _ ->
        params
    end
  end

  defp can_subscribe_biweekly_report?(user) do
    Billing.user_has_product_access?(user.id, Product.product_sanbase()) or
      Billing.user_has_product_access?(user.id, Product.product_api())
  end

  # max emails per day = 200, max telegram per day = 1000
  defp do_update_settings(
         user,
         %{alerts_per_day_limit: %{"email" => email_limit, "telegram" => telegram_limit}} =
           params
       )
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

        settings_update(user.id, Map.put(params, :alerts_per_day_limit, limits))
    end
  end

  defp do_update_settings(_, %{alerts_per_day_limit: _}) do
    {:error, "Invalid values for alerts_per_day_limit"}
  end

  defp do_update_settings(%User{id: id}, params) do
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

  @doc "Returns the stored refinement prompt for a user, or nil if not set."
  @spec get_ai_refinement_prompt(non_neg_integer()) :: String.t() | nil
  def get_ai_refinement_prompt(user_id) do
    case Repo.get_by(__MODULE__, user_id: user_id) do
      nil ->
        nil

      %__MODULE__{settings: settings} when is_map(settings) ->
        Map.get(
          settings,
          :ai_description_refinement_prompt,
          Map.get(settings, "ai_description_refinement_prompt")
        )

      _ ->
        nil
    end
  end

  @doc """
  Stores a user's AI description refinement prompt.

  Delegates persistence to `settings_update/2`.
  Passing `nil` or an empty string clears the per-user override.

  Returns `{:ok, term()}` on success and `{:error, term()}` on validation/persistence errors.

  ## Examples

      iex> Sanbase.Accounts.UserSettings.set_ai_refinement_prompt(42, "Focus on DeFi context")
      {:ok, _}

      iex> Sanbase.Accounts.UserSettings.set_ai_refinement_prompt(42, nil)
      {:ok, _}
  """
  @spec set_ai_refinement_prompt(non_neg_integer(), String.t() | nil) ::
          {:ok, term()} | {:error, term()}
  def set_ai_refinement_prompt(user_id, prompt) do
    settings_update(user_id, %{
      ai_description_refinement_prompt: normalize_refinement_prompt(prompt)
    })
  end

  defp normalize_refinement_prompt(nil), do: nil

  defp normalize_refinement_prompt(prompt) when is_binary(prompt) do
    case String.trim(prompt) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Write the settings that hold a list subscription without emitting Mailjet
  events and without syncing the list.

  Used by `Sanbase.Email.ListSubscription`, which owns the list sync and calls
  Mailjet itself.
  """
  @spec put_list_settings(non_neg_integer(), map()) :: {:ok, term()} | {:error, term()}
  def put_list_settings(user_id, params) do
    settings_update(user_id, params, emit_events: false, sync_lists: false)
  end

  defp settings_update(user_id, params, opts \\ []) do
    {list_change, params} = split_list_change(params, opts)

    Repo.transaction(fn ->
      # A list change also writes the users row. Lock it before the settings row,
      # in the same order as Sanbase.Accounts.update_terms_and_conditions/2, so
      # concurrent changes for the same user cannot deadlock.
      if list_change, do: lock_user(user_id)

      # The settings are stored as one JSON document that is written as a whole,
      # so read it under a lock to not overwrite a concurrent change.
      changeset =
        from(us in __MODULE__, where: us.user_id == ^user_id, lock: "FOR UPDATE")
        |> Repo.one()
        |> case do
          nil ->
            # There are no settings inserted for that user still, create a record
            changeset(%__MODULE__{}, %{user_id: user_id, settings: params})

          %__MODULE__{} = us ->
            changeset(us, %{settings: params})
        end

      with {:ok, %__MODULE__{} = us} <- Repo.insert_or_update(changeset),
           {:ok, list_changed?} <- maybe_change_list(user_id, list_change) do
        us = if list_change, do: Repo.get_by!(__MODULE__, user_id: user_id), else: us
        {us, changeset, list_changed?}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {%__MODULE__{} = us, changeset, list_changed?}} ->
        if Keyword.get(opts, :emit_events, true),
          do: maybe_emit_event_on_changes(user_id, changeset.changes)

        with {list_key, subscribed} <- list_change, true <- list_changed? do
          Sanbase.Email.ListSubscription.notify_mailjet(user_id, list_key, subscribed)
        end

        {:ok, %{us | settings: modify_settings(us)}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp lock_user(user_id) do
    from(u in User, where: u.id == ^user_id, select: u.id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  # The settings of the lists in Sanbase.Email.Lists (e.g. the weekly newsletter
  # toggle) are not written directly. They go through
  # Sanbase.Email.ListSubscription, which keeps every place that holds the
  # subscription in sync, records the consent and calls Mailjet.
  defp split_list_change(params, opts) do
    with true <- Keyword.get(opts, :sync_lists, true),
         {:ok, list_key, subscribed} <- Sanbase.Email.Lists.subscription_change(params) do
      {{list_key, subscribed}, Sanbase.Email.Lists.drop_settings_keys(params)}
    else
      _ -> {nil, params}
    end
  end

  defp maybe_change_list(_user_id, nil = _list_change), do: {:ok, false}

  defp maybe_change_list(user_id, {list_key, subscribed}) do
    Sanbase.Email.ListSubscription.change(user_id, list_key, subscribed, :settings_toggle)
  end

  defp maybe_emit_event_on_changes(user_id, %{settings: settings}) do
    settings_changes = settings.changes

    email_lists_keys = [
      :is_subscribed_biweekly_report,
      :is_subscribed_monthly_newsletter,
      :is_subscribed_metric_updates
    ]

    for key <- Map.keys(settings_changes), key in email_lists_keys do
      Sanbase.Email.MailjetEventEmitter.emit_event(
        {:ok, user_id},
        _event_type = key,
        Map.put(%{}, key, settings_changes[key])
      )
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

    %{
      us.settings
      | has_telegram_connected: us.settings.telegram_chat_id != nil,
        alerts_per_day_limit: alerts_per_day_limit
    }
  end

  defp user_settings_for(%{user_settings: %{settings: _}} = user, opts) do
    user =
      case Keyword.get(opts, :force, false) do
        false -> user
        true -> Repo.preload(user, [:user_settings], force: true)
      end

    user.user_settings
  end

  defp user_settings_for(%User{id: user_id}, _opts) do
    case Repo.get_by(__MODULE__, user_id: user_id) do
      nil ->
        changeset(%__MODULE__{}, %{user_id: user_id, settings: %{}})
        |> Repo.insert!()

      %__MODULE__{} = us ->
        us
    end
  end

  defp do_can_self_reset_api_rate_limits?(nil = _last_self_reset_at), do: true

  defp do_can_self_reset_api_rate_limits?(%DateTime{} = last_self_reset_at) do
    dt_threshold = DateTime.utc_now() |> DateTime.add(-@self_reset_api_rate_limits_cooldown, :day)

    DateTime.compare(last_self_reset_at, dt_threshold) != :gt
  end
end
