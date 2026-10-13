defmodule SanbaseWeb.Graphql.SubcommentsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, root} = Sanbase.Comment.create(user.id, "root comment", nil)
    {:ok, sub1} = Sanbase.Comment.create(user.id, "sub 1", root.id)
    {:ok, sub2} = Sanbase.Comment.create(user.id, "sub 2", sub1.id)

    %{conn: conn, root: root, sub1: sub1, sub2: sub2}
  end

  test "subcomments returns the subcomments tree", context do
    %{conn: conn, root: root, sub1: sub1, sub2: sub2} = context

    query = """
    {
      subcomments(commentId: #{root.id}) { id }
    }
    """

    result = execute_query(conn, query, "subcomments")

    ids = Enum.map(result, & &1["id"])
    assert Enum.sort(ids) == Enum.sort([sub1.id, sub2.id])
  end

  test "subcomments respects the limit argument", context do
    %{conn: conn, root: root, sub1: sub1} = context

    query = """
    {
      subcomments(commentId: #{root.id}, limit: 1) { id }
    }
    """

    result = execute_query(conn, query, "subcomments")

    assert [%{"id" => id}] = result
    assert id == sub1.id
  end

  test "subcomments with a non-integer commentId returns an empty list", %{conn: conn} do
    query = """
    {
      subcomments(commentId: "abc") { id }
    }
    """

    assert execute_query(conn, query, "subcomments") == []
  end
end
