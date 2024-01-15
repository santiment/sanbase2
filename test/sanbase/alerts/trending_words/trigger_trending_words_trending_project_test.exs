defmodule Sanbase.Alert.TriggerTrendingWordsTrendingProjectTest do
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
    project = insert(:project)

    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{trending_project: true},
      target: %{slug: project.slug}
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
      project: project,
      trigger_trending_words: trigger_trending_words
    ]
  end

  test "evaluate trending words triggers", context do
    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [%{word: context.project.name |> String.upcase(), score: 10}] ++
           top_words()}
      end do
      [triggered] =
        TrendingWordsTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert context.trigger_trending_words.id == triggered.id
      payload = triggered.trigger.settings.payload |> Map.values() |> List.first()

      assert payload =~
               "**#{context.project.name}** is in the top 10 trending words on crypto social media."
    end
  end

  test "signal setting cooldown works for trending words", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _, _ ->
        {:ok, [%{word: context.project.name |> String.downcase(), score: 10}] ++ top_words()}
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
