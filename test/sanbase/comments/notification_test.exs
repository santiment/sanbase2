defmodule Sanbase.Comments.NotificationTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Comments.EntityComment
  alias Sanbase.Comments.Notification

  @default_avatar "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png"

  setup do
    author = insert(:user)
    post = insert(:published_post, user: author)
    user = insert(:user)

    timeline_event =
      insert(:timeline_event,
        post: post,
        user: author,
        event_type: Sanbase.Timeline.TimelineEvent.publish_insight_type()
      )

    chart_configuration = insert(:chart_configuration, user: author, is_public: true)
    watchlist = insert(:watchlist, user: author, is_public: true)
    screener = insert(:watchlist, user: author, is_screener: true, is_public: true)

    {:ok,
     user: user,
     author: author,
     post: post,
     timeline_event: timeline_event,
     chart_configuration: chart_configuration,
     watchlist: watchlist,
     screener: screener}
  end

  test "comments and likes", context do
    [user2, user3] = [insert(:user), insert(:user)]

    assert {:ok, comment1} =
             EntityComment.create_and_link(
               :insight,
               context.post.id,
               context.user.id,
               nil,
               "comment1"
             )

    EntityComment.create_and_link(:insight, context.post.id, user2.id, nil, "comment2")

    assert {:ok, comment3} =
             EntityComment.create_and_link(
               :insight,
               context.post.id,
               user3.id,
               comment1.id,
               "subcomment"
             )

    assert {:ok, _} =
             EntityComment.create_and_link(
               :chart_configuration,
               context.chart_configuration.id,
               user2.id,
               nil,
               "chart layout comment"
             )

    assert {:ok, _} =
             EntityComment.create_and_link(
               :watchlist,
               context.watchlist.id,
               user2.id,
               nil,
               "watchlist comment"
             )

    assert {:ok, _} =
             EntityComment.create_and_link(
               :watchlist,
               context.screener.id,
               user2.id,
               nil,
               "screener comment"
             )

    insight2 = insert(:post)
    user5 = insert(:user)
    insert(:vote, post: context.post, user: context.user)
    insert(:vote, post: context.post, user: build(:user))
    insert(:vote, post: insight2, user: user5)
    insert(:vote, watchlist: context.watchlist, user: build(:user))
    insert(:vote, chart_configuration: context.chart_configuration, user: build(:user))
    result = Notification.notify_users_map()

    assert result[insight2.user.email] == %{
             comments: [],
             comments_count: 0,
             likes: [
               %{
                 avatar_url: @default_avatar,
                 entity: "insight",
                 entity_id: insight2.id,
                 link: "https://app-stage.santiment.net/insights/read/#{insight2.id}",
                 rest: false,
                 title: insight2.title,
                 usernames: "@#{user5.username}",
                 likes_count: 1
               }
             ],
             likes_count: 1,
             username: "@#{insight2.user.username}"
           }

    assert result[context.user.email] == %{
             comments: [
               %{
                 avatar_url: @default_avatar,
                 comment_id: comment3.id,
                 comment_text: "subcomment",
                 entity: "insight",
                 link: "https://insights.santiment.net/read/#{context.post.id}",
                 reply_to_text: "reply",
                 title: context.post.title,
                 type: "reply",
                 username: "@#{user3.username}"
               }
             ],
             comments_count: 1,
             likes: [],
             likes_count: 0,
             username: "@#{context.user.username}"
           }

    author_data = result[context.author.email]
    assert author_data.comments_count == 6
    assert author_data.likes_count == 4
  end
end
