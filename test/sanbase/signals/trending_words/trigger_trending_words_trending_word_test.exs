defmodule Sanbase.Alert.TriggerTrendingWordsTrendingWordTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Alert.Evaluator

  alias Sanbase.Alert.Trigger.TrendingWordsTriggerSettings

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{trending_word: true},
      target: %{word: ["san", "santiment"]}
    }

    {:ok, trigger_trending_words} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: false,
        cooldown: "1d",
        settings: trending_words_settings
      })

    [
      user: user,
      trigger_trending_words: trigger_trending_words
    ]
  end

  test "evaluate trending words triggers", context do
    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _ ->
        {:ok, [%{word: "Santiment", score: 10}] ++ top_words()}
      end do
      [triggered] =
        TrendingWordsTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert context.trigger_trending_words.id == triggered.id
      payload = triggered.trigger.settings.payload |> Map.values() |> List.first()
      assert payload =~ "The word **santiment** is in the trending words"
    end
  end

  test "signal setting cooldown works for trending words", _context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _ ->
        {:ok, [%{word: "sANtiment", score: 10}] ++ top_words()}
      end do
      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~
               "In total 1/1 trending_words alerts were sent successfully"

      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~ "There were no trending_words alerts triggered"
    end
  end

  test "cache works when more than 1 word is triggered", _context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _ ->
        {:ok, [%{word: "santiment", score: 10}, %{word: "san", score: 11}] ++ top_words()}
      end do
      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~
               "In total 1/1 trending_words alerts were sent successfully"

      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~ "There were no trending_words alerts triggered"
    end
  end

  test "payload is correct when more than 1 word is triggered", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _ ->
        {:ok, [%{word: "santiment", score: 10}, %{word: "san", score: 11}] ++ top_words()}
      end do
      [triggered] =
        TrendingWordsTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert context.trigger_trending_words.id == triggered.id
      payload = triggered.trigger.settings.payload |> Map.values() |> List.first()
      assert payload =~ "The words **san** and **santiment** are in the trending words"
    end
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
