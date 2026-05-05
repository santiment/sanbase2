defmodule Sanbase.Alert.TriggerSendingTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{UserTrigger, Scheduler}
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
