defmodule Sanbase.Signals.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator

  alias Sanbase.Signals.Trigger.{
    DailyActiveAddressesSettings,
    TrendingWordsTriggerSettings
  }

  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signals.Evaluator.Cache.clear()

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
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    trigger_settings2 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 200.0,
      repeating: false
    }

    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      trigger_time: Time.to_iso8601(Time.utc_now())
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings1
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings2
      })

    {:ok, trigger_trending_words} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: false,
        settings: trending_words_settings
      })

    [
      user: user,
      trigger1: trigger1,
      trigger2: trigger2,
      trigger_trending_words: trigger_trending_words
    ]
  end

  test "all of daily active addresses signals triggered", context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 20}}]
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert length(rest) == 0
      assert context.trigger1.id == triggered1.id
      assert context.trigger2.id == triggered2.id
    end
  end

  test "only some of daily active addresses signals triggered", context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 30}}]
      end do
      [triggered | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 1 signal triggered
      assert length(rest) == 0
      assert context.trigger2.id == triggered.id
    end
  end

  test "none of daily active addresses signals triggered", _context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 100}}]
      end do
      triggered =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 0 signals triggered
      assert length(triggered) == 0
    end
  end

  test "evaluate trending words triggers", context do
    with_mock TrendingWordsTriggerSettings, [:passthrough],
      get_data: fn _ ->
        {:ok,
         [
           %{score: 1740.2647984845628, word: "bat"},
           %{score: 792.9209638684719, word: "coinbase"},
           %{score: 208.48182966076172, word: "mana"},
           %{score: 721.8164660673655, word: "mth"},
           %{score: 837.0034350090417, word: "xlm"}
         ]}
      end do
      [triggered] =
        TrendingWordsTriggerSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      assert context.trigger_trending_words.id == triggered.id
      assert String.contains?(triggered.trigger.settings.payload.trending_words, "coinbase")
    end
  end
end
