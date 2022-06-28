defmodule Sanbase.Comments.NotificationTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Comments.{EntityComment, Notification}

  setup do
    author = insert(:user, email: "author@santiment.net")
    post = insert(:post, user: author)
    user = insert(:user)

    timeline_event =
      insert(:timeline_event,
        post: post,
        user: author,
        event_type: Sanbase.Timeline.TimelineEvent.publish_insight_type()
      )

    chart_configuration = insert(:chart_configuration, user: author)
    watchlist = insert(:watchlist, user: author)
    screener = insert(:watchlist, user: author, is_screener: true)

    {:ok,
     user: user,
     author: author,
     post: post,
     timeline_event: timeline_event,
     chart_configuration: chart_configuration,
     watchlist: watchlist,
     screener: screener}
  end

  test "comments notification map", context do
    [user2, user3, user4] = [insert(:user), insert(:user), insert(:user)]

    {:ok, comment1} =
      EntityComment.create_and_link(:insight, context.post.id, context.user.id, nil, "comment1")

    EntityComment.create_and_link(:insight, context.post.id, user2.id, nil, "comment2")

    {:ok, comment3} =
      EntityComment.create_and_link(
        :insight,
        context.post.id,
        user3.id,
        comment1.id,
        "subcomment"
      )

    {:ok, comment4} =
      EntityComment.create_and_link(
        :timeline_event,
        context.timeline_event.id,
        user4.id,
        nil,
        "an event comment"
      )

    {:ok, comment5} =
      EntityComment.create_and_link(
        :chart_configuration,
        context.chart_configuration.id,
        user2.id,
        nil,
        "chart layout comment"
      )

    EntityComment.create_and_link(
      :watchlist,
      context.watchlist.id,
      user2.id,
      nil,
      "watchlist comment"
    )

    {:ok, comment7} =
      EntityComment.create_and_link(
        :watchlist,
        context.screener.id,
        user2.id,
        nil,
        "screener comment"
      )

    comment_notification = Notification.build_ntf_events_map() |> IO.inspect()

    assert true

    # assert comment_notification.last_insight_comment_id == entity_id(comment3.id)
    # assert comment_notification.last_timeline_event_comment_id == entity_id(comment4.id)
    # assert comment_notification.last_chart_configuration_comment_id == entity_id(comment5.id)
    # assert comment_notification.last_watchlist_comment_id == entity_id(comment7.id)

    # author_data = comment_notification.notify_users_map[context.author.email]
    # assert length(author_data) == 7

    # author_events =
    #   Enum.map(author_data, fn %{event: event} -> event end)
    #   |> Enum.filter(&(&1 == "ntf_author"))

    # assert length(author_events) == 7

    # assert Enum.map(comment_notification.notify_users_map[context.user.email], fn %{event: event} ->
    #          event
    #        end) == ["ntf_previously_commented", "ntf_reply"]
  end

  test "comments and likes", context do
    {:ok, comment1} =
      EntityComment.create_and_link(:insight, context.post.id, context.user.id, nil, "comment1")

    Notification.comments_ntf_map() |> IO.inspect()

    insert(:vote, post: context.post, user: context.user)
    insert(:vote, post: context.post, user: build(:user))
    Notification.votes_ntf_map() |> IO.inspect()

    assert true
  end

  defp entity_id(comment_id) do
    (Sanbase.Repo.get_by(Sanbase.Comment.PostComment, comment_id: comment_id) ||
       Sanbase.Repo.get_by(Sanbase.Comment.TimelineEventComment, comment_id: comment_id) ||
       Sanbase.Repo.get_by(Sanbase.Comment.ChartConfigurationComment, comment_id: comment_id) ||
       Sanbase.Repo.get_by(Sanbase.Comment.WatchlistComment, comment_id: comment_id)).id
  end
end
