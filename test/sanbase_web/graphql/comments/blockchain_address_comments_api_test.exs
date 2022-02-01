defmodule SanbaseWeb.Graphql.BlockchainAddressCommentsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  import Sanbase.CommentsApiHelper

  @opts [entity_type: :blockchain_address, extra_fields: ["blockchainAddressId"]]
  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    blockchain_address = insert(:blockchain_address)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, blockchain_address: blockchain_address}
  end

  test "commentsCount on blockchain address", context do
    %{conn: conn, blockchain_address: blockchain_address} = context
    assert comments_count(conn, blockchain_address.id) == 0

    create_comment(conn, blockchain_address.id, "some content", @opts)
    assert comments_count(conn, blockchain_address.id) == 1

    create_comment(conn, blockchain_address.id, "some content", @opts)
    create_comment(conn, blockchain_address.id, "some content", @opts)
    create_comment(conn, blockchain_address.id, "some content", @opts)
    assert comments_count(conn, blockchain_address.id) == 4

    create_comment(conn, blockchain_address.id, "some content", @opts)
    assert comments_count(conn, blockchain_address.id) == 5
  end

  test "comment a blockchain address", context do
    %{blockchain_address: blockchain_address, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice blockchain_address"

    comment = create_comment(conn, blockchain_address.id, content, @opts)

    comments = get_comments(other_user_conn, blockchain_address.id, @opts)

    assert comment["blockchainAddressId"] |> Sanbase.Math.to_integer() == blockchain_address.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, blockchain_address: blockchain_address} = context

    content = "nice blockchain_address"
    new_content = "updated content"

    comment = create_comment(conn, blockchain_address.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)
    comments = get_comments(conn, blockchain_address.id, @opts)

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
    %{conn: conn, blockchain_address: blockchain_address} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice blockchain_address"
    comment = create_comment(conn, blockchain_address.id, content, @opts)
    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, blockchain_address.id, @opts)
    blockchain_address_comment = comments |> List.first()

    assert blockchain_address_comment["user"]["id"] != comment["user"]["id"]

    assert blockchain_address_comment["user"]["id"] |> Sanbase.Math.to_integer() ==
             fallback_user.id

    assert blockchain_address_comment["content"] != comment["content"]
    assert blockchain_address_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, blockchain_address: blockchain_address} = context
    c1 = create_comment(conn, blockchain_address.id, "some content", @opts)

    opts = Keyword.put(@opts, :parent_id, c1["id"])
    c2 = create_comment(conn, blockchain_address.id, "some content", opts)

    opts = Keyword.put(@opts, :parent_id, c2["id"])
    create_comment(conn, blockchain_address.id, "some content", opts)

    [comment, subcomment1, subcomment2] =
      get_comments(conn, blockchain_address.id, @opts)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp comments_count(conn, blockchain_address_id) do
    query = """
    {
      blockchainAddress(selector: {id: #{blockchain_address_id}}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "blockchainAddress", "commentsCount"])
  end
end
