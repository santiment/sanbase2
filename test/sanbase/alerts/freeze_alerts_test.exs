defmodule Sanbase.Alerts.FreezeAlertsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Alert.UserTrigger

  setup do
    project = insert(:random_erc20_project)

    user =
      insert(:user,
        email: "test@gmail.com",
        user_settings: %{settings: %{alert_notify_telegram: true}}
      )

    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: project.slug},
      channel: "telegram",
      operation: %{above: 300}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    [
      trigger: trigger,
      trigger_settings: trigger_settings,
      project: project,
      user: user
    ]
  end

  defp update_inserted_at(trigger, datetime) do
    Ecto.Changeset.change(trigger, %{inserted_at: datetime})
    |> Sanbase.Repo.update!()
  end

  defp naive_days_ago(days) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> Timex.shift(days: -days)
  end

  test "does not freeze alerts created sooner than 30 days ago", context do
    %{trigger: trigger} = context

    trigger = update_inserted_at(trigger, naive_days_ago(20))

    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert UserTrigger.frozen?(trigger) == false
  end

  test "freeze alerts created more than 30 days ago", context do
    %{trigger: trigger} = context

    trigger = update_inserted_at(trigger, naive_days_ago(31))

    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert {:error, error_msg} = UserTrigger.frozen?(trigger)
    assert error_msg =~ "is frozen"
  end

  test "does not freeze sanbase pro user alerts", context do
    %{user: user, trigger: trigger} = context

    trigger = update_inserted_at(trigger, naive_days_ago(31))
    insert(:subscription_pro_sanbase, user: user)

    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert UserTrigger.frozen?(trigger) == false
  end

  test "does not freeze @santiment.net user's alerts", context do
    %{user: user, trigger: trigger} = context
    # bypass email candidate verification
    Ecto.Changeset.change(user, %{email: "test@santiment.net"}) |> Sanbase.Repo.update!()
    trigger = update_inserted_at(trigger, naive_days_ago(31))
    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert UserTrigger.frozen?(trigger) == false
  end

  for subscription_factory <- [
        :subscription_business_pro_monthly,
        :subscription_business_max_monthly
      ] do
    test "does not freeze #{subscription_factory} user alerts", context do
      %{user: user, trigger: trigger} = context

      trigger = update_inserted_at(trigger, naive_days_ago(31))
      insert(unquote(subscription_factory), user: user)

      Sanbase.Alert.Job.freeze_alerts()

      assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
      assert UserTrigger.frozen?(trigger) == false
    end
  end

  test "unfreeze alerts of a user who bought Business Pro", context do
    %{user: user, trigger: trigger} = context

    trigger = update_inserted_at(trigger, naive_days_ago(31))
    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert {:error, error_msg} = UserTrigger.frozen?(trigger)
    assert error_msg =~ "is frozen"

    insert(:subscription_business_pro_monthly, user: user)
    Sanbase.Alert.Job.unfreeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert UserTrigger.frozen?(trigger) == false
  end

  test "freezes alerts of a SanAPI PRO user", context do
    %{user: user, trigger: trigger} = context

    trigger = update_inserted_at(trigger, naive_days_ago(31))
    insert(:subscription_pro, user: user)

    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert {:error, error_msg} = UserTrigger.frozen?(trigger)
    assert error_msg =~ "is frozen"
  end

  test "unfreeze alerts in case the billing event is not handled", context do
    %{user: user, trigger: trigger} = context

    trigger = update_inserted_at(trigger, naive_days_ago(31))
    insert(:subscription_pro_sanbase, user: user)

    Sanbase.Alert.Job.freeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert UserTrigger.frozen?(trigger) == false

    # Rever the is_frozen back to true. This simulates the case when the event
    # is emitted but is not handled. This can happen if the pod restarts after
    # the event is emitted and before it's handled.
    UserTrigger.update_changeset(trigger, %{trigger: %{is_frozen: true}})
    |> Sanbase.Repo.update!()

    Sanbase.Alert.Job.unfreeze_alerts()

    assert {:ok, trigger} = UserTrigger.by_user_and_id(trigger.user_id, trigger.id)
    assert UserTrigger.frozen?(trigger) == false
  end
end
