defmodule SanbaseWeb.Graphql.PaywalledInsightApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.Post

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "paywalled insights" do
    setup do
      text = Stream.cycle(["alabala"]) |> Enum.take(200) |> Enum.join(" ")
      author = insert(:user)

      post =
        insert(:post,
          text: text,
          user: author,
          state: Post.approved_state(),
          is_paywall_required: true
        )

      query = """
      {
        insight(id: #{post.id}) {
          text
          textPreview
        }
      }
      """

      {:ok, text: text, author: author, post: post, query: query}
    end

    test "with logged in user without pro subscription", context do
      result = context.conn |> post("/graphql", query_skeleton(context.query, "post"))
      insight = json_response(result, 200)["data"]["insight"]

      assert insight["text"] == nil
      assert insight["textPreview"] =~ "alabala"
    end

    test "with logged in user with pro subscription", context do
      insert(:subscription_pro_sanbase, user: context.user)
      result = context.conn |> post("/graphql", query_skeleton(context.query, "post"))
      insight = json_response(result, 200)["data"]["insight"]

      assert insight["text"] == context.post.text
      assert insight["textPreview"] == nil
    end

    test "with not logged in user", context do
      result = build_conn() |> post("/graphql", query_skeleton(context.query, "post"))
      insight = json_response(result, 200)["data"]["insight"]

      assert insight["text"] == nil
      assert insight["textPreview"] =~ "alabala"
    end

    test "when the current user is the author of the insight", context do
      conn = setup_jwt_auth(build_conn(), context.author)
      result = conn |> post("/graphql", query_skeleton(context.query, "post"))
      insight = json_response(result, 200)["data"]["insight"]

      assert insight["text"] == context.post.text
      assert insight["textPreview"] == nil
    end
  end
end
