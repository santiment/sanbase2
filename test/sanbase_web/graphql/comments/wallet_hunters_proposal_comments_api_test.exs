defmodule SanbaseWeb.Graphql.WalletHuntersProposalCommentsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.CommentsApiHelper

  alias Sanbase.WalletHunters.Proposal
  @opts [entity_type: :wallet_hunters_proposal, extra_fields: ["proposalId"]]

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

  test "commentsCount on a wallet hunters proposal", context do
    %{conn: conn, proposal: proposal} = context

    # Mock to avoid a parity call
    Sanbase.Mock.prepare_mock2(&Proposal.fetch_by_proposal_id/1, {:ok, proposal})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert comments_count(conn, proposal.id) == 0

      create_comment(conn, proposal.id, "some content", @opts)
      assert comments_count(conn, proposal.id) == 1

      create_comment(conn, proposal.id, "some content", @opts)
      create_comment(conn, proposal.id, "some content", @opts)
      create_comment(conn, proposal.id, "some content", @opts)
      assert comments_count(conn, proposal.id) == 4

      create_comment(conn, proposal.id, "some content", @opts)
      assert comments_count(conn, proposal.id) == 5
    end)
  end

  test "comment a wallet hunters proposal", context do
    %{proposal: proposal, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice proposal"
    comment = create_comment(conn, proposal.id, content, @opts)
    comments = get_comments(other_user_conn, proposal.id, @opts)

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

    comment = create_comment(conn, proposal.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)
    comments = get_comments(conn, proposal.id, @opts)

    assert comment["editedAt"] == nil
    assert updated_comment["editedAt"] != nil
    edited_at = NaiveDateTime.from_iso8601!(updated_comment["editedAt"])
    assert Sanbase.TestUtils.datetime_close_to(edited_at, Timex.now(), 1, :seconds) == true

    assert comment["content"] == content
    assert updated_comment["content"] == new_content
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("content") == new_content
  end

  test "delete a comment", context do
    %{conn: conn, proposal: proposal} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice proposal"
    comment = create_comment(conn, proposal.id, content, @opts)
    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, proposal.id, @opts)
    proposal_comment = comments |> List.first()

    assert proposal_comment["user"]["id"] != comment["user"]["id"]
    assert proposal_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert proposal_comment["content"] != comment["content"]
    assert proposal_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, proposal: proposal} = context
    c1 = create_comment(conn, proposal.id, "some content", @opts)

    opts = Keyword.put(@opts, :parent_id, c1["id"])
    c2 = create_comment(conn, proposal.id, "other content", opts)

    opts = Keyword.put(@opts, :parent_id, c2["id"])
    create_comment(conn, proposal.id, "other content2", opts)

    [comment, subcomment1, subcomment2] =
      get_comments(conn, proposal.id, @opts)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp comments_count(conn, post_id) do
    query = """
    {
      walletHuntersProposal(id: #{post_id}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "walletHuntersProposal", "commentsCount"])
  end
end
