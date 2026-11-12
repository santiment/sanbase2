defmodule SanbaseWeb.Graphql.PrivateEntityCommentsApiTest do
  @moduledoc """
  SECURITY_ANALYSIS.md C4: comments inherit the visibility of their entity.
  Comments on a private watchlist, dashboard, chart configuration or an
  unpublished insight must not be readable by other users or anonymously —
  neither by entity id, nor through the listing without an id, nor through
  `subcomments`.
  """
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Comments.EntityComment

  setup do
    owner = insert(:user)
    other = insert(:user)

    %{
      owner: owner,
      owner_conn: setup_jwt_auth(build_conn(), owner),
      other_conn: setup_jwt_auth(build_conn(), other),
      anon_conn: build_conn()
    }
  end

  # Private entities a non-owner must not see comments of, and a public twin.
  defp entities(owner) do
    [
      {:watchlist, "WATCHLIST", insert(:watchlist, user: owner, is_public: false),
       insert(:watchlist, user: owner, is_public: true)},
      {:dashboard, "DASHBOARD", insert(:dashboard, user: owner, is_public: false),
       insert(:dashboard, user: owner, is_public: true)},
      {:chart_configuration, "CHART_CONFIGURATION",
       insert(:chart_configuration, user: owner, is_public: false),
       insert(:chart_configuration, user: owner, is_public: true)},
      {:insight, "INSIGHT", insert(:post, user: owner), insert(:published_post, user: owner)}
    ]
  end

  # Linked directly: the owner can't create comments on an unpublished insight
  # through the API, but existing rows (e.g. an insight unpublished later) can.
  defp comment_on(owner, entity_type, entity_id, content, parent_id \\ nil) do
    {:ok, comment} = Sanbase.Comment.create(owner.id, content, parent_id)
    {:ok, _} = EntityComment.link(entity_type, entity_id, comment.id)
    comment
  end

  defp comments(conn, entity_type_enum, id) do
    id_arg = if id, do: "id: #{id}", else: ""

    execute_query(
      conn,
      "{ comments(entityType: #{entity_type_enum} #{id_arg}) { id content } }",
      "comments"
    )
  end

  defp subcomments(conn, comment_id) do
    execute_query(conn, "{ subcomments(commentId: #{comment_id}) { id content } }", "subcomments")
  end

  test "comments of a private entity are hidden from other users and anonymous", context do
    for {entity_type, enum, private, _public} <- entities(context.owner) do
      comment_on(context.owner, entity_type, private.id, "secret #{entity_type}")

      assert comments(context.other_conn, enum, private.id) == [],
             "#{entity_type}: another user read private comments"

      assert comments(context.anon_conn, enum, private.id) == [],
             "#{entity_type}: anonymous read private comments"

      assert [%{"content" => "secret " <> _}] = comments(context.owner_conn, enum, private.id),
             "#{entity_type}: the owner must still see their comments"
    end
  end

  test "comments of a public entity stay readable by everyone", context do
    for {entity_type, enum, _private, public} <- entities(context.owner) do
      comment_on(context.owner, entity_type, public.id, "public #{entity_type}")

      for conn <- [context.other_conn, context.anon_conn, context.owner_conn] do
        assert [%{"content" => "public " <> _}] = comments(conn, enum, public.id),
               "#{entity_type}: public comments must stay readable"
      end
    end
  end

  test "the listing without an id includes only public entities' comments", context do
    for {entity_type, enum, private, public} <- entities(context.owner) do
      comment_on(context.owner, entity_type, private.id, "secret #{entity_type}")
      comment_on(context.owner, entity_type, public.id, "public #{entity_type}")

      for conn <- [context.anon_conn, context.other_conn, context.owner_conn] do
        contents = comments(conn, enum, nil) |> Enum.map(& &1["content"])

        refute "secret #{entity_type}" in contents,
               "#{entity_type}: the id-less listing leaked a private comment"

        assert "public #{entity_type}" in contents
      end
    end
  end

  test "subcomments of a private entity's comment are hidden from non-owners", context do
    for {entity_type, _enum, private, public} <- entities(context.owner) do
      private_root = comment_on(context.owner, entity_type, private.id, "secret root")
      comment_on(context.owner, entity_type, private.id, "secret reply", private_root.id)

      public_root = comment_on(context.owner, entity_type, public.id, "public root")
      comment_on(context.owner, entity_type, public.id, "public reply", public_root.id)

      assert subcomments(context.other_conn, private_root.id) == [], "#{entity_type}"
      assert subcomments(context.anon_conn, private_root.id) == [], "#{entity_type}"

      assert [%{"content" => "secret reply"}] =
               subcomments(context.owner_conn, private_root.id)

      assert [%{"content" => "public reply"}] = subcomments(context.anon_conn, public_root.id)
    end
  end

  test "a non-existent entity or comment returns an empty list", context do
    assert comments(context.anon_conn, "DASHBOARD", 999_999_999) == []
    assert subcomments(context.anon_conn, 999_999_999) == []
  end
end
