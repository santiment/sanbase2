defmodule SanbaseWeb.Graphql.WalletHuntersProposalCommentApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    clean_task_supervisor_children()

    user = insert(:user)

    proposal =
      insert(:wallet_hunters_proposal,
        proposal_id: 2,
        user: user,
        hunter_address: "0x26caae548b7cecf98da12ccaaa633d6d140447aa",
        transaction_id: "0x2"
      )

    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, proposal: proposal}
  end

  test "comment a wallet hunters proposal", context do
    %{proposal: proposal, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice proposal"

    comment = create_comment(conn, proposal.id, nil, content)

    comments = proposal_comments(other_user_conn, proposal.id)

    assert comment["proposalId"] |> Sanbase.Math.to_integer() == proposal.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, proposal: proposal} = context

    content = "nice proposal"
    new_content = "updated content"

    comment = create_comment(conn, proposal.id, nil, content)
    updated_comment = update_comment(conn, comment["id"], new_content)
    comments = proposal_comments(conn, proposal.id)

    assert comment["editedAt"] == nil
    assert updated_comment["editedAt"] != nil

    assert Sanbase.TestUtils.datetime_close_to(
             updated_comment["editedAt"]
             |> NaiveDateTime.from_iso8601!(),
             Timex.now(),
             1,
             :seconds
           ) == true

    assert comment["content"] == content
    assert updated_comment["content"] == new_content
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("content") == new_content
  end

  test "delete a comment", context do
    %{conn: conn, proposal: proposal} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice proposal"
    comment = create_comment(conn, proposal.id, nil, content)
    delete_comment(conn, comment["id"])

    comments = proposal_comments(conn, proposal.id)
    proposal_comment = comments |> List.first()

    assert proposal_comment["user"]["id"] != comment["user"]["id"]
    assert proposal_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert proposal_comment["content"] != comment["content"]
    assert proposal_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, proposal: proposal} = context
    c1 = create_comment(conn, proposal.id, nil, "some content")
    c2 = create_comment(conn, proposal.id, c1["id"], "other content")
    create_comment(conn, proposal.id, c2["id"], "other content2")

    [comment, subcomment1, subcomment2] =
      proposal_comments(conn, proposal.id)
      |> Enum.sort_by(&(&1["id"] |> String.to_integer()))

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp create_comment(conn, proposal_id, parent_id, content) do
    mutation = """
    mutation {
      createComment(
        entityType: WALLET_HUNTERS_PROPOSAL
        id: #{proposal_id}
        parentId: #{parent_id || "null"}
        content: "#{content}") {
          id
          content
          proposalId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    execute_mutation(conn, mutation, "createComment")
  end

  defp update_comment(conn, comment_id, content) do
    mutation = """
    mutation {
      updateComment(
        commentId: #{comment_id}
        content: "#{content}") {
          id
          content
          proposalId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    execute_mutation(conn, mutation, "updateComment")
  end

  defp delete_comment(conn, comment_id) do
    mutation = """
    mutation {
      deleteComment(commentId: #{comment_id}) {
        id
        content
        proposalId
        user{ id username email }
        subcommentsCount
        insertedAt
        editedAt
      }
    }
    """

    execute_mutation(conn, mutation, "deleteComment")
  end

  defp proposal_comments(conn, proposal_id) do
    query = """
    {
      comments(
        entityType: WALLET_HUNTERS_PROPOSAL
        id: #{proposal_id}
        cursor: {type: BEFORE, datetime: "#{Timex.now()}"}) {
          id
          content
          proposalId
          parentId
          rootParentId
          user{ id username email }
          subcommentsCount
      }
    }
    """

    execute_query(conn, query, "comments")
  end
end
