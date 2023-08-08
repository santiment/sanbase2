defmodule Sanbase.Alert.TriggerTrendingWordsWatchlistTargetTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.UserList
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Alert.Evaluator

  alias Sanbase.Alert.Trigger.TrendingWordsTriggerSettings

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    p1 = insert(:random_project)
    p2 = insert(:random_project)

    {:ok, user_list} = UserList.create_user_list(user, %{name: "my_user_list", color: :green})

    UserList.update_user_list(
      user,
      %{
        id: user_list.id,
        list_items: [%{project_id: p1.id}, %{project_id: p2.id}]
      }
    )

    trending_words_settings = %{
      type: TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{trending_project: true},
      target: %{watchlist_id: user_list.id}
    }

    {:ok, trigger_trending_words} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: false,
        settings: trending_words_settings
      })

    [
      user: user,
      p1: p1,
      p2: p2,
      trigger_trending_words: trigger_trending_words
    ]
  end

  test "evaluate trending words triggers", context do
    with_mock Sanbase.SocialData.TrendingWords, [:passthrough],
      get_currently_trending_words: fn _, _ ->
        {:ok, [%{word: context.p1.ticker, score: 10}] ++ top_words()}
      end do
      [triggered] =
        TrendingWordsTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert context.trigger_trending_words.id == triggered.id

      payload =
        triggered.trigger.settings.payload
        |> Map.values()
        |> List.first()

      assert payload =~
               "**#{context.p1.name}** is in the top 10 trending words on crypto social media."
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
