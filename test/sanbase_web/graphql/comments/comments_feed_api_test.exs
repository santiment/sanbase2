defmodule SanbaseWeb.Graphql.Comments.CommentsFeedApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Comments.EntityComment

  setup do
    insert(:insights_fallback_user)

    user = insert(:user)

    blockchain_address = insert(:blockchain_address)
    unpublished_insight = insert(:post, user: user)
    insight = insert(:published_post, user: user)
    insight2 = insert(:published_post, user: user)
    chart_configuration = insert(:chart_configuration, user: user, is_public: true)
    chart_configuration2 = insert(:chart_configuration, user: user, is_public: false)

    conn = setup_jwt_auth(build_conn(), user)

    %{
      conn: conn,
      user: user,
      insight: insight,
      insight2: insight2,
      unpublished_insight: unpublished_insight,
      blockchain_address: blockchain_address,
      chart_configuration: chart_configuration,
      chart_configuration2: chart_configuration2
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
    {:error, _} =
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

    {:ok, chart_configuration_comment} =
      EntityComment.create_and_link(
        :chart_configuration,
        context.chart_configuration.id,
        context.user.id,
        nil,
        "some comment5"
      )

    {:ok, _} =
      EntityComment.create_and_link(
        :chart_configuration,
        context.chart_configuration2.id,
        context.user.id,
        nil,
        "some comment on private chart layout - must not be seen"
      )

    assert {:ok, _} = Sanbase.Insight.Post.delete(context.insight2.id, context.user)
    assert {:error, _} = Sanbase.Insight.Post.by_id(context.insight2.id, [])

    query = comments_feed_query()

    comments = execute_query(context.conn, query, "commentsFeed")

    assert comments == [
             %{
               "blockchainAddress" => nil,
               "content" => chart_configuration_comment.content,
               "id" => chart_configuration_comment.id,
               "insertedAt" =>
                 chart_configuration_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => nil,
               "chartConfiguration" => %{"id" => context.chart_configuration.id}
             },
             %{
               "blockchainAddress" => %{
                 "address" => context.blockchain_address.address,
                 "id" => context.blockchain_address.id
               },
               "content" => ba_comment.content,
               "id" => ba_comment.id,
               "insertedAt" =>
                 ba_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => nil,
               "chartConfiguration" => nil
             },
             %{
               "blockchainAddress" => nil,
               "content" => insight_comment.content,
               "id" => insight_comment.id,
               "insertedAt" =>
                 insight_comment.inserted_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> DateTime.to_iso8601(),
               "insight" => %{"id" => context.insight.id},
               "chartConfiguration" => nil
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
        blockchainAddress { id address }
        chartConfiguration { id }
      }
    }
    """
  end
end
