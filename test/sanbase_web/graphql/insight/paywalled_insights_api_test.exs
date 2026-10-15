defmodule SanbaseWeb.Graphql.PaywalledInsightApiTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.Post

  setup do
    user = insert(:user)
    role_san_family = insert(:role_san_family)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, role_san_family: role_san_family}
  end

  describe "filter paywalled when fetching insight by id" do
    setup do
      text = Stream.cycle(["alabala"]) |> Enum.take(200) |> Enum.join(" ")
      author = insert(:user)

      post =
        insert(:published_post,
          text: text,
          user: author,
          state: Post.approved_state(),
          is_paywall_required: true
        )

      query = """
      {
        insight(id: #{post.id}) {
          text
          isPaywallRequired
        }
      }
      """

      {:ok, text: text, author: author, post: post, query: query}
    end

    test "with logged in user without pro subscription", context do
      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] != context.post.text
      assert insight["text"] =~ "alabala"
    end

    test "with logged in user with basic subscription", context do
      insert(:subscription_basic_sanbase, user: context.user)
      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "with logged in user with pro subscription", context do
      insert(:subscription_pro_sanbase, user: context.user)
      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "with logged in user with Sanapi PRO subscription", context do
      subscription =
        insert(:subscription_pro, user: context.user)
        |> Sanbase.Repo.preload(:plan)

      assert Sanbase.Billing.Plan.SanbaseAccessChecker.can_access_paywalled_insights?(
               subscription
             )

      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "with logged in user with SANBASE MAX subscription", context do
      subscription =
        insert(:subscription_max_sanbase, user: context.user)
        |> Sanbase.Repo.preload(:plan)

      assert Sanbase.Billing.Plan.SanbaseAccessChecker.can_access_paywalled_insights?(
               subscription
             )

      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "with logged in user with BUSINESS_PRO subscription", context do
      subscription =
        insert(:subscription_business_pro_monthly, user: context.user)
        |> Sanbase.Repo.preload(:plan)

      assert Sanbase.Billing.Plan.SanbaseAccessChecker.can_access_paywalled_insights?(
               subscription
             )

      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "with logged in user with BUSINESS_MAX subscription", context do
      subscription =
        insert(:subscription_business_max_monthly, user: context.user)
        |> Sanbase.Repo.preload(:plan)

      assert Sanbase.Billing.Plan.SanbaseAccessChecker.can_access_paywalled_insights?(
               subscription
             )

      insight = execute_query(context.conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "with not logged in user", context do
      insight = execute_query(build_conn(), context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] != context.post.text
      assert insight["text"] =~ "alabala"
    end

    test "when the current user is the author of the insight", context do
      conn = setup_jwt_auth(build_conn(), context.author)
      insight = execute_query(conn, context.query, "insight")

      assert insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
    end

    test "when paywall is not required", context do
      insight = create_insight(context, %{is_paywall_required: false})
      query = insight_by_id_query(insight.id)
      insight = execute_query(context.conn, query, "insight")

      refute insight["isPaywallRequired"]
      assert insight["text"] == context.post.text
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
      insight2 = create_insight(context, %{is_paywall_required: true})

      insights = execute_query(context.conn, context.query, "allInsights")

      [result_insight1] = Enum.filter(insights, &(!&1["isPaywallRequired"]))
      [result_insight2] = Enum.filter(insights, & &1["isPaywallRequired"])

      assert result_insight1["text"] == insight1.text

      assert result_insight2["text"] != insight2.text
      assert result_insight2["text"] =~ "alabala"
    end
  end

  test "the paywall access is checked once per response, not per insight", context do
    author = insert(:user)
    text = Stream.cycle(["alabala"]) |> Enum.take(200) |> Enum.join(" ")
    query = "{ allInsights { text pulseText isPaywallRequired } }"

    create_insight(%{text: text, author: author}, %{})
    one_insight_queries = count_subscription_queries(fn -> execute_query(context.conn, query) end)

    for _ <- 1..4, do: create_insight(%{text: text, author: author}, %{})

    {insights, five_insights_queries} =
      count_subscription_queries(fn -> execute_query(context.conn, query, "allInsights") end,
        return: true
      )

    assert length(insights) == 5
    assert Enum.all?(insights, &(&1["text"] != text))
    assert five_insights_queries == one_insight_queries
  end

  describe "filter paywalled in other fields returning insights" do
    setup do
      text = Stream.cycle(["alabala"]) |> Enum.take(200) |> Enum.join(" ")
      author = insert(:user)

      {:ok, text: text, author: author}
    end

    test "featuredInsights", context do
      insight = create_insight(context, %{})
      :ok = Sanbase.FeaturedItem.update_item(insight, true)

      query = "{ featuredInsights { id text isPaywallRequired } }"
      [result] = execute_query(context.conn, query, "featuredInsights")

      assert result["isPaywallRequired"]
      assert result["text"] != insight.text
      assert result["text"] =~ "alabala"
    end

    test "getUser insights", context do
      insight = create_insight(context, %{})

      query = """
      {
        getUser(selector: {id: #{context.author.id}}) {
          insights { id text isPaywallRequired }
        }
      }
      """

      %{"insights" => [result]} = execute_query(context.conn, query, "getUser")

      assert result["isPaywallRequired"]
      assert result["text"] != insight.text
      assert result["text"] =~ "alabala"
    end

    test "getMostRecent insights", context do
      insight = create_insight(context, %{published_at: DateTime.utc_now()})

      query = """
      {
        getMostRecent(types: [INSIGHT], page: 1, pageSize: 10) {
          data { insight { id text isPaywallRequired } }
        }
      }
      """

      %{"data" => [%{"insight" => result}]} =
        execute_query(context.conn, query, "getMostRecent")

      assert result["isPaywallRequired"]
      assert result["text"] != insight.text
      assert result["text"] =~ "alabala"
    end
  end

  # Counts the queries to the subscriptions table made by the test process, which
  # also handles the request.
  defp count_subscription_queries(fun, opts \\ []) do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      [:sanbase, :repo, :query],
      fn _event, _measurements, %{source: source}, _config ->
        if self() == test_pid and source == "subscriptions",
          do: send(test_pid, :subscription_query)
      end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler_id)
    count = count_messages(:subscription_query, 0)

    if Keyword.get(opts, :return, false), do: {result, count}, else: count
  end

  defp count_messages(message, count) do
    receive do
      ^message -> count_messages(message, count + 1)
    after
      0 -> count
    end
  end

  defp insight_by_id_query(insight_id) do
    """
    {
      insight(id: #{insight_id}) {
        text
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
        shortDesc
        isPaywallRequired
      }
    }
    """
  end

  defp create_insight(context, params) do
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
