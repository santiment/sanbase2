defmodule Sanbase.Signal.TriggerPayloadTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Evaluator
  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signal.Evaluator.Cache.clear()

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    trigger_settings1 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      operation: %{above: 5},
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings1
      })

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

    [
      user: user,
      trigger1: trigger1,
      datetimes: datetimes
    ]
  end

  test "payload is extended", context do
      payload = "Some payload"

      target_list =
        Enum.zip(context.datetimes, [100, 120, 100, 80, 20, 10, 5])
        |> IO.inspect()
        |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})
        |> IO.inspect()

      with_mock DailyActiveAddressesSettings, [:passthrough],
        get_data: fn _ ->
          [{"santiment", target_list}]
        end do
        trigger_settings1 = %{
          type: "daily_active_addresses",
          target: %{slug: "santiment"},
          channel: "telegram",
          time_window: "1d",
          operation: %{percent_up: 2}
        }

        {:ok, trigger1} =
          UserTrigger.create_user_trigger(context.user, %{
            title: "Generic title",
            is_public: true,
            cooldown: "12h",
            settings: trigger_settings1
          })

        UserTrigger.update_user_trigger(context.user, %{
          id: trigger1.id,
          last_triggered: %{}
        })

        type = DailyActiveAddressesSettings.type()

        triggered =
          DailyActiveAddressesSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Sanbase.Signal.Evaluator.run(type)

        assert triggered =~ payload
      end
  end
end
