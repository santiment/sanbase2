defmodule Sanbase.Alert.TriggerTrendingWordsSendAtPredefiendTimeTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{UserTrigger, HistoricalActivity}
  alias Sanbase.Alert.Evaluator

  alias Sanbase.Alert.Trigger.TrendingWordsTriggerSettings

  @moduletag capture_log: true

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    send_at = Time.utc_now() |> Time.add(60) |> Time.to_iso8601()

    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{send_at_predefined_time: true, trigger_time: send_at}
    }

    {:ok, trigger_trending_words} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: false,
        settings: trending_words_settings
      })

    [
      user: user,
      trigger_trending_words: trigger_trending_words
    ]
  end

  test "validate trigger_time", context do
    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{send_at_predefined_time: true, trigger_time: "8:00:00"}
    }

    assert UserTrigger.create_user_trigger(context.user, %{
             title: "Generic title",
             is_public: false,
             settings: trending_words_settings
           }) ==
             {:error,
              "Trigger structure is invalid. Key `settings` is not valid. Reason: [\"8:00:00 is not a valid ISO8601 time\"]"}
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
      payload = triggered.trigger.settings.payload |> Map.values() |> List.first()
      assert String.contains?(payload, "coinbase")
    end
  end

  test "signal setting cooldown works for trending words", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData.TrendingWords, [],
      get_currently_trending_words: fn _ ->
        {:ok, top_words()}
      end do
      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~
               "In total 1/1 trending_words alerts were sent successfully"

      user_signal = HistoricalActivity |> Sanbase.Repo.all() |> List.first()
      assert user_signal.user_id == context.user.id

      payload = user_signal.payload |> Map.values() |> List.first()
      assert String.contains?(payload, "coinbase")

      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~ "There were no trending_words alerts triggered"
    end
  end

  test "Non active alerts are filtered", context do
    UserTrigger.update_user_trigger(context.user.id, %{
      id: context.trigger_trending_words.id,
      is_active: false
    })

    assert capture_log(fn ->
             Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
           end) =~ "There are no active alerts of type trending_words to be run"
  end

  test "Non repeating alerts are deactivated", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    UserTrigger.update_user_trigger(context.user.id, %{
      id: context.trigger_trending_words.id,
      is_repeating: false
    })

    with_mock Sanbase.SocialData.TrendingWords, [],
      get_currently_trending_words: fn _ ->
        {:ok, top_words()}
      end do
      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(TrendingWordsTriggerSettings)
             end) =~
               "In total 1/1 trending_words alerts were sent successfully"

      {:ok, ut} =
        UserTrigger.get_trigger_by_id(context.user.id, context.trigger_trending_words.id)

      refute ut.trigger.is_active
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
