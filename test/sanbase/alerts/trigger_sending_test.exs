defmodule Sanbase.Alert.TriggerSendingTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{HistoricalActivity, UserTrigger, Scheduler}
  alias Sanbase.Alert.Trigger.MetricTriggerSettings

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user =
      insert(:user,
        email: "test@example.com",
        user_settings: %{settings: %{alert_notify_telegram: true}}
      )

    Sanbase.Accounts.UserSettings.update_settings(user, %{alert_notify_email: true})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = insert(:random_project)

    [user: user, project: project]
  end

  test "send to a webhook", context do
    %{user: user, project: project} = context

    {:ok, trigger} =
      create_trigger(user, project.slug,
        channel: [%{"webhook" => "https://example.com/webhook_url"}]
      )

    mock_fun =
      [
        fn -> {:ok, %{project.slug => 10}} end,
        fn -> {:ok, %{project.slug => 15}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 4)

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock2(
      &HTTPoison.post/3,
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      trigger = trigger |> Sanbase.Repo.preload([:user])

      {:ok, user_trigger} = Sanbase.Alert.UserTrigger.by_user_and_id(trigger.user.id, trigger.id)

      last_triggered_dt =
        user_trigger.trigger.last_triggered
        |> Map.get(project.slug)
        |> Sanbase.Utils.DateTime.from_iso8601!()

      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), last_triggered_dt, 60, :seconds)
    end)
  end

  describe "unsupported notification channel" do
    test "Sanbase.Alert.send/1 does not raise on a bare \"webhook\" channel and logs the trigger",
         context do
      %{user: user} = context

      user_trigger = %{
        id: 4242,
        user_id: user.id,
        user: user,
        trigger: %{
          id: 4242,
          settings: %{
            channel: "webhook",
            payload: %{"santiment" => "some payload"}
          }
        }
      }

      log =
        capture_log(fn ->
          assert [{"santiment", {:error, error}}] = Sanbase.Alert.Any.send(user_trigger)

          assert error == %{
                   reason: :unsupported_notification_channel,
                   channel: "webhook",
                   user_id: user.id,
                   trigger_id: 4242
                 }
        end)

      assert log =~ "Unsupported alert notification channel"
      assert log =~ "user_trigger_id=4242"
    end

    test "Sanbase.Alert.send/1 does not raise when channel list contains an unsupported value",
         context do
      %{user: user} = context

      user_trigger = %{
        id: 99,
        user_id: user.id,
        user: user,
        trigger: %{
          id: 99,
          settings: %{
            channel: ["email", "telegram_channel"],
            payload: %{"santiment" => "p1", "ethereum" => "p2"}
          }
        }
      }

      capture_log(fn ->
        results = Sanbase.Alert.Any.send(user_trigger)

        # email branch returns either :ok per identifier (when user has email +
        # opt-in) or per-identifier error tuples; the catch-all for
        # "telegram_channel" must contribute one error tuple per payload
        # identifier with our unsupported reason.
        unsupported =
          Enum.filter(results, fn
            {_, {:error, %{reason: :unsupported_notification_channel}}} -> true
            _ -> false
          end)

        assert length(unsupported) == 2
      end)
    end
  end

  describe "channel validation at create time" do
    @tag capture_log: true
    test "rejects bare \"webhook\" string", context do
      %{user: user, project: project} = context

      assert {:error, _} =
               UserTrigger.create_user_trigger(user, %{
                 title: "x",
                 is_public: false,
                 cooldown: "1h",
                 settings: %{
                   type: "metric_signal",
                   metric: "active_addresses_24h",
                   target: %{slug: project.slug},
                   channel: "webhook",
                   time_window: "1d",
                   operation: %{above_or_equal: 5}
                 }
               })
    end

    @tag capture_log: true
    test "rejects bare \"telegram_channel\" string", context do
      %{user: user, project: project} = context

      assert {:error, _} =
               UserTrigger.create_user_trigger(user, %{
                 title: "x",
                 is_public: false,
                 cooldown: "1h",
                 settings: %{
                   type: "metric_signal",
                   metric: "active_addresses_24h",
                   target: %{slug: project.slug},
                   channel: "telegram_channel",
                   time_window: "1d",
                   operation: %{above_or_equal: 5}
                 }
               })
    end

    test "accepts webhook in map form", context do
      %{user: user, project: project} = context

      assert {:ok, _} =
               UserTrigger.create_user_trigger(user, %{
                 title: "x",
                 is_public: false,
                 cooldown: "1h",
                 settings: %{
                   type: "metric_signal",
                   metric: "active_addresses_24h",
                   target: %{slug: project.slug},
                   channel: %{"webhook" => "https://example.com/hook"},
                   time_window: "1d",
                   operation: %{above_or_equal: 5}
                 }
               })
    end
  end

  describe "IP webhook destinations at runtime" do
    @tag capture_log: true
    test "scheduler deactivates alert whose webhook host is an IP address", context do
      %{user: user, project: project} = context

      # Create-time validation rejects IP hosts, so plant a legacy trigger by
      # updating the embed directly, bypassing the validation.
      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      plant_webhook_url!(trigger.id, "https://8.8.8.8/hook")

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.post/3,
        {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        Scheduler.run_alert(MetricTriggerSettings)

        {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)
        assert user_trigger.trigger.is_active == false
      end)
    end

    @tag capture_log: true
    test "alert with a bad webhook URL and another channel stays active", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug,
          channel: ["telegram", %{"webhook" => "https://example.com/hook"}]
        )

      plant_webhook_url_keeping_channels!(trigger.id, "https://8.8.8.8/hook")

      mock_fun =
        [
          fn -> {:ok, %{project.slug => 10}} end,
          fn -> {:ok, %{project.slug => 15}} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 4)

      Sanbase.Mock.prepare_mock(Sanbase.Metric, :aggregated_timeseries_data, mock_fun)
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Telegram.send_message/2,
        {:ok, ~s({"result": {}})}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        Scheduler.run_alert(MetricTriggerSettings)

        {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)
        assert user_trigger.trigger.is_active == true
      end)
    end

    @tag capture_log: true
    test "send/1 rejects webhook URL with a public IP host", context do
      user_trigger = build_webhook_user_trigger(context.user, "https://8.8.8.8/hook")

      assert [{"santiment", {:error, error}}] = Sanbase.Alert.Any.send(user_trigger)
      assert %{reason: :webhook_url_not_valid, error: reason} = error
      assert reason =~ "is an IP address"
    end

    @tag capture_log: true
    test "alert with invalid legacy webhook URL is deactivated on the first send", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      plant_webhook_url!(trigger.id, "http://example.com/hook")

      run_scheduler_with_webhook_response(project, 200)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)
      assert user_trigger.trigger.is_active == false
    end

    @tag capture_log: true
    test "send/1 rejects legacy http webhook URL", context do
      user_trigger = build_webhook_user_trigger(context.user, "http://example.com/hook")

      assert [{"santiment", {:error, error}}] = Sanbase.Alert.Any.send(user_trigger)
      assert %{reason: :webhook_url_not_valid, error: reason} = error
      assert reason =~ "must use the https scheme"
    end
  end

  describe "failing alerts auto-disable" do
    @tag capture_log: true
    test "failed webhook send starts the failing streak", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      run_scheduler_with_webhook_response(project, 500)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

      assert %DateTime{} = user_trigger.trigger.failing_since

      assert Sanbase.TestUtils.datetime_close_to(
               Timex.now(),
               user_trigger.trigger.failing_since,
               60,
               :seconds
             )

      assert user_trigger.trigger.failed_attempts == 1
      assert user_trigger.trigger.consecutive_failed_days == 1
      assert user_trigger.trigger.last_failed_on == Date.utc_today()
      assert user_trigger.trigger.is_active == true
    end

    @tag capture_log: true
    test "failed retry does not create activity from a stale successful delivery", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      # The old delivery must remain outside the cooldown so this run evaluates
      # and attempts another send, but it is not a new historical activity.
      previous_delivery =
        DateTime.utc_now()
        |> DateTime.add(-24 * 60 * 60, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      plant_trigger_state!(trigger.id, %{last_triggered: %{project.slug => previous_delivery}})

      run_scheduler_with_webhook_response(project, 500)

      assert Sanbase.Repo.aggregate(HistoricalActivity, :count) == 0
    end

    @tag capture_log: true
    test "successful send clears the failing streak", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      plant_trigger_state!(trigger.id, %{
        failing_since: days_ago(3),
        failed_attempts: 42,
        consecutive_failed_days: 3,
        last_failed_on: Date.add(Date.utc_today(), -1)
      })

      run_scheduler_with_webhook_response(project, 200)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

      assert user_trigger.trigger.failing_since == nil
      assert user_trigger.trigger.failed_attempts == 0
      assert user_trigger.trigger.consecutive_failed_days == 0
      assert user_trigger.trigger.last_failed_on == nil
      assert user_trigger.trigger.is_active == true
    end

    @tag capture_log: true
    test "alert failing on 7 days in a row is deactivated", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      plant_trigger_state!(trigger.id, %{
        failing_since: days_ago(7),
        failed_attempts: 60,
        consecutive_failed_days: 6,
        last_failed_on: Date.add(Date.utc_today(), -1)
      })

      run_scheduler_with_webhook_response(project, 500)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

      assert user_trigger.trigger.consecutive_failed_days == 7
      assert user_trigger.trigger.is_active == false
    end

    @tag capture_log: true
    test "a day without failures breaks the chain", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      # Last failure 3 days ago - the failure-free days in between restart
      # the chain from 1 instead of reaching 7.
      plant_trigger_state!(trigger.id, %{
        failing_since: days_ago(10),
        failed_attempts: 60,
        consecutive_failed_days: 6,
        last_failed_on: Date.add(Date.utc_today(), -3)
      })

      run_scheduler_with_webhook_response(project, 500)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

      assert user_trigger.trigger.consecutive_failed_days == 1
      assert user_trigger.trigger.failed_attempts == 61
      assert user_trigger.trigger.is_active == true

      # The failing_since marker is preserved - there was still no success
      assert Sanbase.TestUtils.datetime_close_to(
               days_ago(10),
               user_trigger.trigger.failing_since,
               60,
               :seconds
             )
    end

    @tag capture_log: true
    test "multiple failures within the same day count as one day", context do
      %{user: user, project: project} = context

      {:ok, trigger} =
        create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/hook"}])

      plant_trigger_state!(trigger.id, %{
        failing_since: days_ago(6),
        failed_attempts: 40,
        consecutive_failed_days: 6,
        last_failed_on: Date.utc_today()
      })

      run_scheduler_with_webhook_response(project, 500)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

      assert user_trigger.trigger.consecutive_failed_days == 6
      assert user_trigger.trigger.failed_attempts == 41
      assert user_trigger.trigger.is_active == true
    end
  end

  defp run_scheduler_with_webhook_response(project, status_code) do
    mock_fun =
      [
        fn -> {:ok, %{project.slug => 10}} end,
        fn -> {:ok, %{project.slug => 15}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 4)

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock2(
      &HTTPoison.post/3,
      {:ok, %HTTPoison.Response{status_code: status_code, body: ""}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)
    end)
  end

  describe "stamp_last_triggered/3" do
    test "stamps identifiers without touching existing ones", context do
      %{user: user, project: project} = context

      {:ok, trigger} = create_trigger(user, project.slug, channel: ["telegram"])

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      :ok = UserTrigger.stamp_last_triggered(trigger.id, "santiment", now)
      :ok = UserTrigger.stamp_last_triggered(trigger.id, ["ethereum", "bitcoin"], now)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

      assert user_trigger.trigger.last_triggered |> Map.keys() |> Enum.sort() ==
               ["bitcoin", "ethereum", "santiment"]

      stamped_dt =
        user_trigger.trigger.last_triggered
        |> Map.get("santiment")
        |> Sanbase.Utils.DateTime.from_iso8601!()

      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), stamped_dt, 60, :seconds)
    end

    test "stamps legacy rows missing the last_triggered key", context do
      %{user: user, project: project} = context

      {:ok, trigger} = create_trigger(user, project.slug, channel: ["telegram"])

      Sanbase.Repo.query!(
        "UPDATE user_triggers SET trigger = trigger - 'last_triggered' WHERE id = $1",
        [trigger.id]
      )

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      :ok = UserTrigger.stamp_last_triggered(trigger.id, "santiment", now)

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)
      assert Map.has_key?(user_trigger.trigger.last_triggered, "santiment")
    end
  end

  defp build_webhook_user_trigger(user, webhook_url) do
    %{
      id: 555,
      user_id: user.id,
      user: user,
      trigger: %{
        id: 555,
        settings: %{
          channel: %{webhook: webhook_url},
          payload: %{"santiment" => "some payload"}
        }
      }
    }
  end

  defp plant_webhook_url!(user_trigger_id, url) do
    ut = Sanbase.Repo.get(UserTrigger, user_trigger_id)
    settings = Map.put(ut.trigger.settings, "channel", [%{"webhook" => url}])

    plant_trigger_state!(user_trigger_id, %{settings: settings})
  end

  defp plant_webhook_url_keeping_channels!(user_trigger_id, url) do
    ut = Sanbase.Repo.get(UserTrigger, user_trigger_id)

    channel =
      ut.trigger.settings
      |> Map.get("channel")
      |> Enum.map(fn
        %{"webhook" => _} -> %{"webhook" => url}
        other -> other
      end)

    settings = Map.put(ut.trigger.settings, "channel", channel)
    plant_trigger_state!(user_trigger_id, %{settings: settings})
  end

  # Update the embedded trigger directly, bypassing the create/update
  # validations, to simulate legacy DB state.
  defp plant_trigger_state!(user_trigger_id, %{} = trigger_attrs) do
    Sanbase.Repo.get(UserTrigger, user_trigger_id)
    |> Sanbase.Repo.preload([:tags])
    |> UserTrigger.update_changeset(%{trigger: trigger_attrs})
    |> Sanbase.Repo.update!()
  end

  defp days_ago(days) do
    Sanbase.Utils.DateTime.days_ago(days) |> DateTime.truncate(:second)
  end

  defp create_trigger(user, slug, opts) do
    metric = Keyword.get(opts, :metric, "active_addresses_24h")
    time_window = Keyword.get(opts, :time_window, "1d")
    channel = Keyword.get(opts, :channel, ["telegram"])

    trigger_settings = %{
      type: "metric_signal",
      metric: metric,
      target: %{slug: slug},
      channel: channel,
      time_window: time_window,
      operation: %{above_or_equal: 5}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    {:ok, trigger}
  end
end
