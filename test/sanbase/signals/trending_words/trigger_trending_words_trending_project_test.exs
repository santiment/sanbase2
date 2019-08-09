defmodule Sanbase.Signal.TriggerTrendingWordsTrendingProjectTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Evaluator

  alias Sanbase.Signal.Trigger.TrendingWordsTriggerSettings

  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signal.Evaluator.Cache.clear()

    user = insert(:user)
    project = insert(:project)

    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{trending_project: true},
      target: %{slug: project.coinmarketcap_id}
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
      get_trending_now: fn _ ->
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
      assert payload =~ "The project **#{context.project.name}** is in the trending words"
      assert payload =~ "Volume and OHCL price chart for the past 90 days"
    end
  end

  test "signal setting cooldown works for trending words", context do
    Tesla.Mock.mock_global(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_trending_now: fn _ ->
        {:ok, [%{word: context.project.name |> String.downcase(), score: 10}] ++ top_words()}
      end do
      assert capture_log(fn ->
               Sanbase.Signal.Scheduler.run_signal(TrendingWordsTriggerSettings)
             end) =~ "In total 1/1 trending_words signals were sent successfully"

      Sanbase.Signal.Evaluator.Cache.clear()

      assert capture_log(fn ->
               Sanbase.Signal.Scheduler.run_signal(TrendingWordsTriggerSettings)
             end) =~ "There were no signals triggered of type"
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
