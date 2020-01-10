defmodule Sanbase.Signal.TriggerPricePercentChangeTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.InfluxdbHelpers

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Signal.{Trigger, UserTrigger, Evaluator}
  alias Sanbase.Signal.Trigger.PricePercentChangeSettings

  @ticker "SAN"
  @cmc_id "santiment"
  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signal.Evaluator.Cache.clear()

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: @ticker,
      slug: @cmc_id,
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    populate_influxdb()

    [
      user: user
    ]
  end

  describe "price percent change" do
    test "moving up - only some triggered", context do
      trigger_settings1 = price_percent_change_settings(%{operation: %{percent_up: 18.0}})
      # should trigger signal
      trigger_settings2 = price_percent_change_settings(%{operation: %{percent_up: 15.0}})

      {:ok, _} = create_trigger(context.user, trigger_settings1)
      {:ok, trigger2} = create_trigger(context.user, trigger_settings2)

      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert trigger2.id == triggered.id
      assert Trigger.triggered?(triggered.trigger) == true
    end

    test "moving down - only some triggered", context do
      ticker_cmc_id = "#{@ticker}_#{@cmc_id}"

      Store.import([
        %Measurement{
          timestamp: Timex.now() |> DateTime.to_unix(:nanosecond),
          fields: %{price_usd: 40, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
          name: ticker_cmc_id
        }
      ])

      # should trigger signal
      trigger_settings1 = price_percent_change_settings(%{operation: %{percent_down: 20.0}})
      trigger_settings2 = price_percent_change_settings(%{operation: %{percent_up: 40.0}})

      {:ok, trigger1} = create_trigger(context.user, trigger_settings1)
      {:ok, _} = create_trigger(context.user, trigger_settings2)

      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert trigger1.id == triggered.id
      assert Trigger.triggered?(triggered.trigger) == true
    end

    test "moving up or move down - percent_up triggered", context do
      trigger_settings =
        price_percent_change_settings(%{
          operation: %{some_of: [%{percent_up: 15}, %{percent_down: 100}]}
        })

      {:ok, trigger} = create_trigger(context.user, trigger_settings)

      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert Trigger.triggered?(triggered.trigger) == true
      assert triggered.id == trigger.id
    end

    test "moving up or move down - percent_down triggered", context do
      Store.import([
        %Measurement{
          timestamp: Timex.now() |> DateTime.to_unix(:nanosecond),
          fields: %{price_usd: 1, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
          name: "#{@ticker}_#{@cmc_id}"
        }
      ])

      trigger_settings =
        price_percent_change_settings(%{
          operation: %{some_of: [%{percent_up: 1500}, %{percent_down: 20}]}
        })

      {:ok, trigger} = create_trigger(context.user, trigger_settings)

      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert Trigger.triggered?(triggered.trigger) == true
      assert triggered.id == trigger.id
    end

    test "move up and move down - nothing triggered", context do
      trigger_settings =
        price_percent_change_settings(%{
          operation: %{none_of: [%{percent_up: 0.001}, %{percent_down: 0.00001}]}
        })

      create_trigger(context.user, trigger_settings)

      assert [] ==
               PricePercentChangeSettings.type()
               |> UserTrigger.get_active_triggers_by_type()
               |> Evaluator.run()
    end
  end

  test "move up and move down - triggered", context do
    trigger_settings =
      price_percent_change_settings(%{
        operation: %{all_of: [%{percent_up: 15}, %{percent_up: 10}]}
      })

    {:ok, trigger} = create_trigger(context.user, trigger_settings)

    [triggered | rest] =
      PricePercentChangeSettings.type()
      |> UserTrigger.get_active_triggers_by_type()
      |> Evaluator.run()

    assert rest == []
    assert Trigger.triggered?(triggered.trigger) == true
    assert triggered.id == trigger.id
  end

  defp populate_influxdb() do
    setup_prices_influxdb()

    ticker_cmc_id = "#{@ticker}_#{@cmc_id}"

    datetime1 = Timex.shift(Timex.now(), hours: -9)
    datetime2 = Timex.shift(Timex.now(), hours: -8)
    datetime3 = Timex.shift(Timex.now(), hours: -7)
    datetime4 = Timex.shift(Timex.now(), hours: -6)
    datetime5 = Timex.shift(Timex.now(), hours: -5)
    datetime6 = Timex.shift(Timex.now(), hours: -4)
    datetime7 = Timex.shift(Timex.now(), hours: -3)
    datetime8 = Timex.shift(Timex.now(), hours: -2)
    datetime9 = Timex.now()

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 20, price_btc: 1000, volume_usd: 200, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 22, price_btc: 1200, volume_usd: 300, marketcap_usd: 800},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 50, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 55, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 53, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 58, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 60, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 59, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime9 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 62, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id
      }
    ])
  end

  defp create_trigger(user, settings) do
    UserTrigger.create_user_trigger(user, %{
      title: "Generic title",
      is_public: true,
      cooldown: "12h",
      settings: settings
    })
  end

  defp price_percent_change_settings(price_opts) do
    Map.merge(
      %{
        type: "price_percent_change",
        target: %{slug: "santiment"},
        channel: "telegram",
        time_window: "6h"
      },
      price_opts
    )
  end
end
