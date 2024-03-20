defmodule SanbaseWeb.Graphql.PaywalledInsightApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.Post
  alias Sanbase.Timeline.TimelineEvent

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

  describe "filter paywalled when fetching all insights and timeline events" do
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

    test "text is filtered in timeline events", context do
      san_author = insert(:user)
      insert(:user_role, user: san_author, role: context.role_san_family)
      insight = create_insight(context, %{user: san_author, is_paywall_required: true})

      timeline_event =
        insert(:timeline_event,
          post: insight,
          user: san_author,
          event_type: TimelineEvent.publish_insight_type()
        )

      events = execute_query(context.conn, timeline_events_query(), "timelineEvents")
      event = events |> hd |> Map.get("events") |> hd
      assert event["post"]["text"] != insight.text
      assert event["post"]["text"] =~ "alabala"

      event =
        execute_query(context.conn, timeline_event_query(timeline_event.id), "timelineEvent")

      assert event["post"]["text"] != insight
      assert event["post"]["text"] =~ "alabala"
    end
  end

  defp timeline_event_query(event_id) do
    """
    {
      timelineEvent(id: #{event_id}) {
        id
        post {
          id
          tags { name }
          text
          isPaywallRequired
        }
      }
    }
    """
  end

  defp timeline_events_query() do
    """
    {
      timelineEvents {
        cursor {
          after
          before
        }
        events {
          id
          post {
            id
            tags { name }
            text
            isPaywallRequired
          }
        }
      }
    }
    """
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
