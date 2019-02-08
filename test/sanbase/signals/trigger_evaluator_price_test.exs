defmodule Sanbase.Signals.EvaluatorPriceTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Signals.{Trigger, UserTrigger, Evaluator}
  alias Sanbase.Signals.Trigger.{PricePercentChangeSettings, PriceAbsoluteChangeSettings}

  @ticker "SAN"
  @cmc_id "santiment"
  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signals.Evaluator.Cache.clear()

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    user = insert(:user)

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: @ticker,
      coinmarketcap_id: @cmc_id,
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    # trigger 1: 10% change last 6 hours
    # trigger 2: above 60 or below 50
    {trigger1, trigger2, trigger3, trigger4} = setup_triggers(user)
    populate_influxdb()

    [
      user: user,
      trigger1: trigger1,
      trigger2: trigger2,
      trigger3: trigger3,
      trigger4: trigger4
    ]
  end

  test "evaluate triggers percent change some triggered", context do
    [triggered | rest] =
      PricePercentChangeSettings.type()
      |> UserTrigger.get_triggers_by_type()
      |> Evaluator.run()

    assert length(rest) == 0
    assert context.trigger1.id == triggered.id
    assert Trigger.triggered?(triggered.trigger) == true
  end

  test "evaluate triggers absolute change some triggered", context do
    [triggered | rest] =
      PriceAbsoluteChangeSettings.type()
      |> UserTrigger.get_triggers_by_type()
      |> Evaluator.run()

    assert length(rest) == 0
    assert context.trigger2.id == triggered.id
    # assert Trigger.triggered?(triggered.trigger) == true
  end

  defp populate_influxdb() do
    ticker_cmc_id = "#{@ticker}_#{@cmc_id}"

    Store.drop_measurement(ticker_cmc_id)

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

  defp setup_triggers(user) do
    trigger_settings1 = %{
      type: "price_percent_change",
      target: "santiment",
      channel: "telegram",
      time_window: "6h",
      percent_threshold: 15.0,
      repeating: false
    }

    trigger_settings2 = %{
      type: "price_absolute_change",
      target: "santiment",
      channel: "telegram",
      above: 60,
      below: 50,
      repeating: false
    }

    trigger_settings3 = %{
      type: "price_percent_change",
      target: "santiment",
      channel: "telegram",
      time_window: "6h",
      percent_threshold: 18.0,
      repeating: false
    }

    trigger_settings4 = %{
      type: "price_absolute_change",
      target: "santiment",
      channel: "telegram",
      above: 70,
      below: 50,
      repeating: false
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings1
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings2
      })

    {:ok, trigger3} =
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings3
      })

    {:ok, trigger4} =
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings4
      })

    {trigger1, trigger2, trigger3, trigger4}
  end
end
