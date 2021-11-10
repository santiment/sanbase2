defmodule SanbaseWeb.Graphql.Comments.CommentsFeedApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Comments.EntityComment

  setup do
    user = insert(:user)
    watchlist = insert(:watchlist)

    blockchain_address = insert(:blockchain_address)
    unpublished_insight = insert(:post, user: user)
    insight = insert(:published_post, user: user)
    insight2 = insert(:published_post, user: user)
    short_url = insert(:short_url)

    timeline_event =
      insert(:timeline_event,
        user_list: watchlist,
        user: user,
        event_type: Sanbase.Timeline.TimelineEvent.update_watchlist_type()
      )

    conn = setup_jwt_auth(build_conn(), user)

    %{
      conn: conn,
      user: user,
      insight: insight,
      insight2: insight2,
      unpublished_insight: unpublished_insight,
      blockchain_address: blockchain_address,
      short_url: short_url,
      timeline_event: timeline_event
    }
  end

  test "comments feed", context do
    # create a comment for an insight that
    # will be deleted before fetching the comments
    {:ok, _} =
      EntityComment.create_and_link(
        :insight,
        context.insight2.id,
        context.user.id,
        nil,
        "some comment on insight that will be deleted"
      )

    # should not appear in the result because the post is
    # not published
    {:ok, _} =
      EntityComment.create_and_link(
        :insight,
        context.unpublished_insight.id,
        context.user.id,
        nil,
        "some comment on unpublished insight"
      )

    {:ok, insight_comment} =
      EntityComment.create_and_link(
        :insight,
        context.insight.id,
        context.user.id,
        nil,
        "some comment1"
      )

    {:ok, ba_comment} =
      EntityComment.create_and_link(
        :blockchain_address,
        context.blockchain_address.id,
        context.user.id,
        nil,
        "some comment2"
      )

    {:ok, short_url_comment} =
      EntityComment.create_and_link(
        :short_url,
        context.short_url.id,
        context.user.id,
        nil,
        "some comment3"
      )

    {:ok, timeline_event_comment} =
      EntityComment.create_and_link(
        :timeline_event,
        context.timeline_event.id,
        context.user.id,
        nil,
        "some comment4"
      )

    assert {:ok, _} = Sanbase.Insight.Post.delete(context.insight2.id, context.user)
    assert {:error, _} = Sanbase.Insight.Post.by_id(context.insight2.id)

    query = comments_feed_query()

    comments = execute_query(context.conn, query, "commentsFeed")

    assert comments == [
             %{
               "blockchainAddress" => nil,
               "content" => timeline_event_comment.content,
               "id" => timeline_event_comment.id |> Integer.to_string(),
               "insertedAt" =>
                 timeline_event_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => nil,
               "shortUrl" => nil,
               "timelineEvent" => %{"id" => context.timeline_event.id |> Integer.to_string()}
             },
             %{
               "blockchainAddress" => nil,
               "content" => short_url_comment.content,
               "id" => short_url_comment.id |> Integer.to_string(),
               "insertedAt" =>
                 short_url_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => nil,
               "shortUrl" => %{"shortUrl" => context.short_url.short_url},
               "timelineEvent" => nil
             },
             %{
               "blockchainAddress" => %{
                 "address" => context.blockchain_address.address,
                 "id" => context.blockchain_address.id
               },
               "content" => ba_comment.content,
               "id" => ba_comment.id |> Integer.to_string(),
               "insertedAt" =>
                 ba_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => nil,
               "shortUrl" => nil,
               "timelineEvent" => nil
             },
             %{
               "blockchainAddress" => nil,
               "content" => insight_comment.content,
               "id" => insight_comment.id |> Integer.to_string(),
               "insertedAt" =>
                 insight_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => %{"id" => context.insight.id |> Integer.to_string()},
               "shortUrl" => nil,
               "timelineEvent" => nil
             }
           ]
  end

  defp comments_feed_query do
    """
    {
      commentsFeed(limit: 5) {
        id
        content
        insertedAt
        insight { id }
        timelineEvent { id }
        shortUrl { shortUrl }
        blockchainAddress { id address }
      }
    }
    """
  end
end
