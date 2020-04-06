defmodule Sanbase.Signal.TriggerPayloadTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  alias Sanbase.Signal.{UserTrigger, Scheduler}
  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  setup_with_mocks([
    {Sanbase.GoogleChart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signal.Evaluator.Cache.clear()
    user = insert(:user, email: "test@example.com")
    Sanbase.Auth.UserSettings.update_settings(user, %{signal_notify_email: true})
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)
    project = insert(:random_project)

    [user: user, project: project, datetimes: datetimes]
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

    with_mocks([
      {DailyActiveAddressesSettings, [:passthrough],
       get_data: fn _ -> [{project.slug, daily_active_addresses}] end},
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(self_pid, {:telegram_to_self, text})
         :ok
       end},
      {Sanbase.MandrillApi, [:passthrough], send: fn _, _, _ -> {:ok, %{"status" => "sent"}} end}
    ]) do
      Scheduler.run_signal(DailyActiveAddressesSettings)

      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ SanbaseWeb.Endpoint.show_signal_url(trigger.id)
      assert_called(Sanbase.MandrillApi.send("signals", "test@example.com", :_))
    end
  end
end
