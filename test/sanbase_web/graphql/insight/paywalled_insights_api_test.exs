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

  describe "filter paywalled when fetching insight by id" do
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
          isPaywallRequired
        }
      }
      """

      {:ok, text: text, author: author, post: post, query: query}
    end

    test "with logged in user without pro subscription", context do
      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == nil
      assert insight["textPreview"] =~ "alabala"
    end

    test "with logged in user with pro subscription", context do
      insert(:subscription_pro_sanbase, user: context.user)
      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
      assert insight["textPreview"] == nil
    end

    test "with not logged in user", context do
      insight = execute_query(build_conn(), context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == nil
      assert insight["textPreview"] =~ "alabala"
    end

    test "when the current user is the author of the insight", context do
      conn = setup_jwt_auth(build_conn(), context.author)
      insight = execute_query(conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
      assert insight["textPreview"] == nil
    end

    test "when paywall is not required", context do
      insight = create_insight(context, %{is_paywall_required: false})
      query = insight_by_id_query(insight.id)
      insight = execute_query(context.conn, query, "insight")

      refute insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
      assert insight["textPreview"] == nil
    end

    test "when there short_desc - use it as text preview", context do
      insight = create_insight(context, %{short_desc: "short description"})
      query = insight_by_id_query(insight.id)
      insight = execute_query(context.conn, query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == nil
      assert insight["shortDesc"] == "short description"
      assert insight["textPreview"] == "short description"
    end
  end

  describe "filter paywalled when fetching all insights" do
    setup do
      text = Stream.cycle(["alabala"]) |> Enum.take(200) |> Enum.join(" ")
      author = insert(:user)
      query = all_insights_query()

      {:ok, text: text, author: author, query: query}
    end

    test "filter text only in paywalled", context do
      insight1 = create_insight(context, %{is_paywall_required: false})
      create_insight(context, %{is_paywall_required: true})

      insights = execute_query(context.conn, context.query, "allInsights")

      [result_insight1] = Enum.filter(insights, &(!&1["isPaywallRequired"]))
      [result_insight2] = Enum.filter(insights, & &1["isPaywallRequired"])

      assert result_insight1["text"] == insight1.text
      assert result_insight1["textPreview"] == nil

      assert result_insight2["text"] == nil
      assert result_insight2["textPreview"] =~ "alabala"
    end
  end

  defp insight_by_id_query(insight_id) do
    """
    {
      insight(id: #{insight_id}) {
        text
        textPreview
        shortDesc
        isPaywallRequired
      }
    }
    """
  end

  defp all_insights_query() do
    """
    {
      allInsights {
        text
        textPreview
        shortDesc
        isPaywallRequired
      }
    }
    """
  end

  defp create_insight(context, params \\ %{}) do
    default_fields = %{
      text: context.text,
      user: context.author,
      state: Post.approved_state(),
      ready_state: Post.published(),
      is_paywall_required: true
    }

    merged_params = Map.merge(default_fields, params)

    insert(:post, merged_params)
  end
end
