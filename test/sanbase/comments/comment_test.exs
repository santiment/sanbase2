defmodule Sanbase.CommentTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Comments.EntityComment
  alias Sanbase.Comment

  @insight_entity_type :insight

  test "add a comment to a post" do
    post = insert(:post)
    user = insert(:user)

    {:ok, comment} =
      EntityComment.create_and_link(@insight_entity_type, post.id, user.id, nil, "some comment")

    post_comments =
      EntityComment.get_comments(@insight_entity_type, post.id, %{cursor: nil, limit: 100})

    assert length(post_comments) == 1
    assert [%{comment: %{id: post_comment_id}}] = post_comments
    assert comment.id == post_comment_id
  end

  test "add a comment to a watchlist" do
    user = insert(:user)

    watchlist = insert(:watchlist, user: user)

    {:ok, comment} =
      EntityComment.create_and_link(
        :watchlist,
        watchlist.id,
        user.id,
        nil,
        "some comment"
      )

    watchlist_comments =
      EntityComment.get_comments(:watchlist, watchlist.id, %{cursor: nil, limit: 100})

    assert length(watchlist_comments) == 1
    assert [%{comment: %{id: watchlist_id}}] = watchlist_comments
    assert comment.id == watchlist_id
  end

  test "add a comment to a chart configuration" do
    user = insert(:user)

    chart_configuration = insert(:chart_configuration, user: user)

    {:ok, comment} =
      EntityComment.create_and_link(
        :chart_configuration,
        chart_configuration.id,
        user.id,
        nil,
        "some comment"
      )

    chart_configuration_comments =
      EntityComment.get_comments(:chart_configuration, chart_configuration.id, %{
        cursor: nil,
        limit: 100
      })

    assert length(chart_configuration_comments) == 1
    assert [%{comment: %{id: chart_configuration_id}}] = chart_configuration_comments
    assert comment.id == chart_configuration_id
  end

  test "add a comment to a wallet hunters proposal" do
    user = insert(:user)

    proposal =
      insert(:wallet_hunters_proposal,
        proposal_id: 2,
        user: user,
        hunter_address: "0x26caae548b7cecf98da12ccaaa633d6d140447aa",
        transaction_id: "0x2"
      )

    {:ok, comment} =
      EntityComment.create_and_link(
        :wallet_hunters_proposal,
        proposal.id,
        user.id,
        nil,
        "some comment"
      )

    proposal_comments =
      EntityComment.get_comments(:wallet_hunters_proposal, proposal.id, %{cursor: nil, limit: 100})

    assert length(proposal_comments) == 1
    [%{comment: %{id: proposal_id}}] = proposal_comments
    assert comment.id == proposal_id
  end

  test "add a comment to a short url" do
    short_url = insert(:short_url)
    user = insert(:user)

    {:ok, comment} =
      EntityComment.create_and_link(:short_url, short_url.id, user.id, nil, "some comment")

    short_url_comments =
      EntityComment.get_comments(:short_url, short_url.id, %{cursor: nil, limit: 100})

    assert length(short_url_comments) == 1
    [%{comment: %{id: short_url_comment_id}}] = short_url_comments
    assert comment.id == short_url_comment_id
  end

  test "add a comment to a timeline event" do
    watchlist = insert(:watchlist)
    user = insert(:user)

    # Timeline event with watchlist
    timeline_event =
      insert(:timeline_event,
        user_list: watchlist,
        user: user,
        event_type: Sanbase.Timeline.TimelineEvent.update_watchlist_type()
      )

    {:ok, comment} =
      EntityComment.create_and_link(
        :timeline_event,
        timeline_event.id,
        user.id,
        nil,
        "some comment"
      )

    timeline_event_comments =
      EntityComment.get_comments(:timeline_event, timeline_event.id, %{cursor: nil, limit: 100})

    assert length(timeline_event_comments) == 1
    [%{comment: %{id: timeline_event_comment_id}}] = timeline_event_comments
    assert comment.id == timeline_event_comment_id
  end

  test "add a comment to a blockchain address" do
    blockchain_address = insert(:blockchain_address)
    user = insert(:user)

    {:ok, comment} =
      EntityComment.create_and_link(
        :blockchain_address,
        blockchain_address.id,
        user.id,
        nil,
        "some comment"
      )

    blockchain_address_comments =
      EntityComment.get_comments(:blockchain_address, blockchain_address.id, %{
        cursor: nil,
        limit: 100
      })

    assert length(blockchain_address_comments) == 1
    [%{comment: %{id: blockchain_address_comment_id}}] = blockchain_address_comments
    assert comment.id == blockchain_address_comment_id
  end

  test "add a sub comment" do
    post = insert(:post)
    user = insert(:user)

    {:ok, comment1} =
      EntityComment.create_and_link(@insight_entity_type, post.id, user.id, nil, "some comment")

    {:ok, comment2} =
      EntityComment.create_and_link(
        @insight_entity_type,
        post.id,
        user.id,
        comment1.id,
        "some comment"
      )

    assert comment2.parent_id == comment1.id
    assert comment2.root_parent_id == comment1.id
  end

  test "update a comment" do
    post = insert(:post)

    content = "some comment"
    updated_content = "updated content"

    {:ok, comment} =
      EntityComment.create_and_link(@insight_entity_type, post.id, post.user_id, nil, content)

    naive_dt_before_update = Timex.shift(NaiveDateTime.utc_now(), seconds: -1)

    {:ok, updated_comment} = Comment.update(comment.id, comment.user_id, updated_content)

    naive_dt_after_update = Timex.shift(NaiveDateTime.utc_now(), seconds: 1)

    assert comment.edited_at == nil
    assert comment.content == content

    assert updated_comment.edited_at != nil
    assert NaiveDateTime.compare(updated_comment.edited_at, naive_dt_before_update) == :gt
    assert NaiveDateTime.compare(naive_dt_after_update, updated_comment.edited_at) == :gt
    assert updated_comment.content == updated_content
  end

  test "delete a comment" do
    post = insert(:post)
    fallback_user = insert(:insights_fallback_user)

    {:ok, comment} =
      EntityComment.create_and_link(
        @insight_entity_type,
        post.id,
        post.user_id,
        nil,
        "some comment"
      )

    {:ok, deleted} = Comment.delete(comment.id, comment.user_id)

    # The `delete` actually anonymizes instead of deleting. This is done so the
    # tree structure and links can be kept
    assert deleted.user_id == fallback_user.id
    assert deleted.content != comment.content
    assert deleted.content =~ "deleted"
  end

  test "root_parent_id is properly inherited" do
    post = insert(:post)
    user = insert(:user)

    {:ok, comment1} =
      EntityComment.create_and_link(@insight_entity_type, post.id, user.id, nil, "some comment")

    {:ok, comment2} =
      EntityComment.create_and_link(
        @insight_entity_type,
        post.id,
        user.id,
        comment1.id,
        "some comment"
      )

    {:ok, comment3} =
      EntityComment.create_and_link(
        @insight_entity_type,
        post.id,
        user.id,
        comment2.id,
        "some comment"
      )

    {:ok, comment4} =
      EntityComment.create_and_link(
        @insight_entity_type,
        post.id,
        user.id,
        comment3.id,
        "some comment"
      )

    assert comment2.parent_id == comment1.id
    assert comment2.root_parent_id == comment1.id

    assert comment3.parent_id == comment2.id
    assert comment3.root_parent_id == comment1.id

    assert comment4.parent_id == comment3.id
    assert comment4.root_parent_id == comment1.id
  end
end
