defmodule Sanbase.Signal.TriggerPayloadTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Signal.{UserTrigger, Scheduler}
  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  setup do
    Sanbase.Signal.Evaluator.Cache.clear()
    user = insert(:user, email: "test@example.com")
    Sanbase.Auth.UserSettings.update_settings(user, %{signal_notify_email: true})
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)
    project = insert(:random_project)

    [user: user, project: project, datetimes: datetimes]
  end

  test "human readable numbers between 1000 and 1,000,000", context do
    %{user: user, project: project, datetimes: datetimes} = context

    daily_active_addresses =
      Enum.zip(datetimes, [100, 120, 100, 80, 20, 10, 10_456])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    trigger_settings = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: ["telegram", "email"],
      time_window: "1d",
      operation: %{above: 10_000}
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    self_pid = self()

    Sanbase.Mock.prepare_mock2(&DailyActiveAddressesSettings.get_data/1, [
      {project.slug, daily_active_addresses}
    ])
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      :ok
    end)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.MandrillApi.send/3, {:ok, %{"status" => "sent"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_signal(DailyActiveAddressesSettings)

      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ "10,456.00"
      assert_called(Sanbase.MandrillApi.send("signals", "test@example.com", :_))
    end)
  end

  test "human readable numbers above 1,000,000", context do
    %{user: user, project: project, datetimes: datetimes} = context

    daily_active_addresses =
      Enum.zip(datetimes, [100, 120, 100, 80, 20, 10, 9_231_100_456])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    trigger_settings = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: ["telegram", "email"],
      time_window: "1d",
      operation: %{above: 10_000}
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    self_pid = self()

    Sanbase.Mock.prepare_mock2(&DailyActiveAddressesSettings.get_data/1, [
      {project.slug, daily_active_addresses}
    ])
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      :ok
    end)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.MandrillApi.send/3, {:ok, %{"status" => "sent"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_signal(DailyActiveAddressesSettings)

      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ "9.23 Billion"
      assert_called(Sanbase.MandrillApi.send("signals", "test@example.com", :_))
    end)
  end

  test "payload is extended", context do
    %{user: user, project: project, datetimes: datetimes} = context

    daily_active_addresses =
      Enum.zip(datetimes, [100, 120, 100, 80, 20, 10, 5])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    trigger_settings = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: ["telegram", "email"],
      time_window: "1d",
      operation: %{above: 5}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    self_pid = self()

    Sanbase.Mock.prepare_mock2(&DailyActiveAddressesSettings.get_data/1, [
      {project.slug, daily_active_addresses}
    ])
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      :ok
    end)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.MandrillApi.send/3, {:ok, %{"status" => "sent"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_signal(DailyActiveAddressesSettings)

      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ SanbaseWeb.Endpoint.show_signal_url(trigger.id)
      assert_called(Sanbase.MandrillApi.send("signals", "test@example.com", :_))
    end)
  end

  test "send to a webhook", context do
    %{user: user, project: project, datetimes: datetimes} = context

    daily_active_addresses =
      Enum.zip(datetimes, [100, 120, 100, 80, 20, 10, 5])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    trigger_settings = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: [%{"webhook" => "url"}],
      time_window: "1d",
      operation: %{above: 5}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    Sanbase.Mock.prepare_mock2(&DailyActiveAddressesSettings.get_data/1, [
      {project.slug, daily_active_addresses}
    ])
    |> Sanbase.Mock.prepare_mock2(
      &HTTPoison.post/2,
      {:ok, %HTTPoison.Response{status_code: 200}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_signal(DailyActiveAddressesSettings)

      trigger = trigger |> Sanbase.Repo.preload([:user])

      {:ok, user_trigger} = Sanbase.Signal.UserTrigger.get_trigger_by_id(trigger.user, trigger.id)

      last_triggered_dt =
        user_trigger.trigger.last_triggered
        |> Map.get(project.slug)
        |> Sanbase.DateTimeUtils.from_iso8601!()

      # Last triggered is rounded to minutes
      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), last_triggered_dt, 60, :seconds)
    end)
  end
end
