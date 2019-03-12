defmodule Sanbase.Signals.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signals.{UserTrigger, HistoricalActivity}
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
      percent_threshold: 300.0
    }

    trigger_settings2 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 200.0
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
        |> UserTrigger.get_active_triggers_by_type()
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
        |> UserTrigger.get_active_triggers_by_type()
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
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 0 signals triggered
      assert length(triggered) == 0
    end
  end

  test "evaluate trending words triggers", context do
    with_mock TrendingWordsTriggerSettings, [:passthrough],
      get_data: fn _ ->
        {:ok, top_words()}
      end do
      [triggered] =
        TrendingWordsTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert context.trigger_trending_words.id == triggered.id
      assert String.contains?(triggered.trigger.settings.payload["all"], "coinbase")
    end
  end

  test "signal setting cooldown works for trending words", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData, [:passthrough],
      trending_words: fn _, _, _, _, _ ->
        {:ok, [%{top_words: top_words()}]}
      end do
      assert capture_log(fn ->
               Sanbase.Signals.Scheduler.run_trending_words_signals()
             end) =~ "In total 1/1 trending_words signals were sent successfully"

      alias Sanbase.Signals.HistoricalActivity
      user_signal = HistoricalActivity |> Sanbase.Repo.all() |> List.first()
      assert user_signal.user_id == context.user.id
      assert String.contains?(user_signal.payload["all"], "coinbase")

      Sanbase.Signals.Evaluator.Cache.clear()

      assert capture_log(fn ->
               Sanbase.Signals.Scheduler.run_trending_words_signals()
             end) =~ "There were no signals triggered of type"
    end
  end

  test "successfull signal is written in signals_historical_activity table", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData, [:passthrough],
      trending_words: fn _, _, _, _, _ ->
        {:ok, [%{top_words: top_words()}]}
      end do
      assert capture_log(fn ->
               Sanbase.Signals.Scheduler.run_trending_words_signals()
             end) =~ "In total 1/1 trending_words signals were sent successfully"

      user_signal = HistoricalActivity |> Sanbase.Repo.all() |> List.first()
      assert user_signal.user_id == context.user.id
      assert String.contains?(user_signal.payload["all"], "coinbase")
    end
  end

  test "Non active signals are filtered", context do
    UserTrigger.update_user_trigger(context.user, %{
      id: context.trigger_trending_words.id,
      active: false
    })

    assert capture_log(fn ->
             Sanbase.Signals.Scheduler.run_trending_words_signals()
           end) =~ "There were no signals triggered of type"
  end

  defp top_words() do
    [
      %{score: 1740.2647984845628, word: "bat"},
      %{score: 792.9209638684719, word: "coinbase"},
      %{score: 208.48182966076172, word: "mana"},
      %{score: 721.8164660673655, word: "mth"},
      %{score: 837.0034350090417, word: "xlm"}
    ]
  end
end
