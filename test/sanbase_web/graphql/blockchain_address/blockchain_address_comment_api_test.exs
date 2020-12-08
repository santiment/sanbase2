defmodule SanbaseWeb.Graphql.BlockchainAddressCommentApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

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

    create_comment(conn, blockchain_address.id, nil, "some content")
    assert comments_count(conn, blockchain_address.id) == 1

    create_comment(conn, blockchain_address.id, nil, "some content")
    create_comment(conn, blockchain_address.id, nil, "some content")
    create_comment(conn, blockchain_address.id, nil, "some content")
    assert comments_count(conn, blockchain_address.id) == 4

    create_comment(conn, blockchain_address.id, nil, "some content")
    assert comments_count(conn, blockchain_address.id) == 5
  end

  test "comment a blockchain address", context do
    %{blockchain_address: blockchain_address, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice blockchain_address"

    comment = create_comment(conn, blockchain_address.id, nil, content)

    comments = get_comments(other_user_conn, blockchain_address.id)

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

    comment = create_comment(conn, blockchain_address.id, nil, content)
    updated_comment = update_comment(conn, comment["id"], new_content)
    comments = get_comments(conn, blockchain_address.id)

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
    %{conn: conn, blockchain_address: blockchain_address} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice blockchain_address"
    comment = create_comment(conn, blockchain_address.id, nil, content)
    delete_comment(conn, comment["id"])

    comments = get_comments(conn, blockchain_address.id)
    blockchain_address_comment = comments |> List.first()

    assert blockchain_address_comment["user"]["id"] != comment["user"]["id"]

    assert blockchain_address_comment["user"]["id"] |> Sanbase.Math.to_integer() ==
             fallback_user.id

    assert blockchain_address_comment["content"] != comment["content"]
    assert blockchain_address_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, blockchain_address: blockchain_address} = context
    c1 = create_comment(conn, blockchain_address.id, nil, "some content")
    c2 = create_comment(conn, blockchain_address.id, c1["id"], "other content")
    create_comment(conn, blockchain_address.id, c2["id"], "other content2")

    [comment, subcomment1, subcomment2] =
      get_comments(conn, blockchain_address.id)
      |> Enum.sort_by(&(&1["id"] |> String.to_integer()))

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp create_comment(conn, blockchain_address_id, parent_id, content) do
    mutation = """
    mutation {
      createComment(
        id: #{blockchain_address_id}
        ENTITY_TYPE: BLOCKCHAIN_ADDRESS
        parentId: #{parent_id || "null"}
        content: "#{content}") {
          id
          content
          blockchainAddressId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "createComment"])
  end

  defp update_comment(conn, comment_id, content) do
    mutation = """
    mutation {
      updateComment(
        commentId: #{comment_id}
        content: "#{content}") {
          id
          content
          blockchainAddressId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "updateComment"])
  end

  defp delete_comment(conn, comment_id) do
    mutation = """
    mutation {
      deleteComment(
        commentId: #{comment_id}) {
          id
          content
          blockchainAddressId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "deleteComment"])
  end

  defp get_comments(conn, blockchain_address_id) do
    query = """
    {
      comments(
        id: #{blockchain_address_id}
        ENTITY_TYPE: BLOCKCHAIN_ADDRESS
        cursor: {type: BEFORE, datetime: "#{Timex.now()}"}) {
          id
          content
          blockchainAddressId
          parentId
          rootParentId
          user{ id username email }
          subcommentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "comments"])
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
