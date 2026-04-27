defmodule SanbaseWeb.Graphql.UserOnboardingTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Accounts.UserOnboarding

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "submitUserOnboarding mutation" do
    test "creates a new onboarding record for the current user", %{conn: conn, user: user} do
      result =
        execute_mutation(
          conn,
          submit_mutation(
            title: "crypto_trader",
            goal: "catch_trends",
            used_tools: ["price_charts", "screeners"],
            uses_behaviour_analysis: "yes"
          )
        )

      assert result == %{
               "title" => "crypto_trader",
               "goal" => "catch_trends",
               "usedTools" => ["price_charts", "screeners"],
               "usesBehaviourAnalysis" => "yes"
             }

      stored = UserOnboarding.for_user(user.id)
      assert stored.title == "crypto_trader"
      assert stored.goal == "catch_trends"
      assert stored.used_tools == ["price_charts", "screeners"]
      assert stored.uses_behaviour_analysis == "yes"
    end

    test "re-submitting upserts the existing record", %{conn: conn, user: user} do
      execute_mutation(
        conn,
        submit_mutation(
          title: "crypto_trader",
          goal: "catch_trends",
          used_tools: ["price_charts"],
          uses_behaviour_analysis: "yes"
        )
      )

      result =
        execute_mutation(
          conn,
          submit_mutation(
            title: "researcher",
            goal: "build_analysis",
            used_tools: ["on_chain_analytics", "social_signals"],
            uses_behaviour_analysis: "no"
          )
        )

      assert result["title"] == "researcher"
      assert result["goal"] == "build_analysis"
      assert result["usedTools"] == ["on_chain_analytics", "social_signals"]
      assert result["usesBehaviourAnalysis"] == "no"

      assert Sanbase.Repo.aggregate(UserOnboarding, :count, :id) == 1
      stored = UserOnboarding.for_user(user.id)
      assert stored.title == "researcher"
    end

    test "rejects an invalid title", %{conn: conn} do
      error =
        execute_mutation_with_error(
          conn,
          submit_mutation(title: "not_a_real_title")
        )

      assert error =~ "title"
    end

    test "rejects an invalid goal", %{conn: conn} do
      error =
        execute_mutation_with_error(
          conn,
          submit_mutation(goal: "totally_made_up")
        )

      assert error =~ "goal"
    end

    test "rejects an invalid uses_behaviour_analysis value", %{conn: conn} do
      error =
        execute_mutation_with_error(
          conn,
          submit_mutation(uses_behaviour_analysis: "maybe")
        )

      assert error =~ "uses_behaviour_analysis"
    end

    test "rejects an invalid element in used_tools", %{conn: conn} do
      error =
        execute_mutation_with_error(
          conn,
          submit_mutation(used_tools: ["price_charts", "definitely_not_a_tool"])
        )

      assert error =~ "used_tools"
    end

    test "is rejected when the user is not authenticated" do
      error =
        execute_mutation_with_error(
          build_conn(),
          submit_mutation(title: "crypto_trader")
        )

      assert error =~ "unauthorized" or error =~ "Unauthorized"
    end
  end

  describe "currentUser.userOnboarding query" do
    test "returns null before any submission", %{conn: conn} do
      result = execute_query(conn, current_user_query(), "currentUser")

      assert result["userOnboarding"] == nil
    end

    test "returns the saved answers after submission", %{conn: conn} do
      execute_mutation(
        conn,
        submit_mutation(
          title: "content_maker",
          goal: "make_better_trade_entries",
          used_tools: ["news_feeds"],
          uses_behaviour_analysis: "not_sure"
        )
      )

      result = execute_query(conn, current_user_query(), "currentUser")

      assert result["userOnboarding"] == %{
               "title" => "content_maker",
               "goal" => "make_better_trade_entries",
               "usedTools" => ["news_feeds"],
               "usesBehaviourAnalysis" => "not_sure"
             }
    end
  end

  defp submit_mutation(fields) do
    input =
      fields
      |> Enum.map(fn
        {:title, v} -> ~s|title: "#{v}"|
        {:goal, v} -> ~s|goal: "#{v}"|
        {:uses_behaviour_analysis, v} -> ~s|usesBehaviourAnalysis: "#{v}"|
        {:used_tools, list} -> "usedTools: #{string_list_to_string(list)}"
      end)
      |> Enum.join(", ")

    """
    mutation {
      submitUserOnboarding(onboarding: {#{input}}) {
        title
        goal
        usedTools
        usesBehaviourAnalysis
      }
    }
    """
  end

  defp current_user_query() do
    """
    {
      currentUser {
        id
        userOnboarding {
          title
          goal
          usedTools
          usesBehaviourAnalysis
        }
      }
    }
    """
  end
end
