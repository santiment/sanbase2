defmodule SanbaseWeb.Graphql.Resolvers.UserResolverPureTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.Graphql.Resolvers.UserResolver

  describe "format_activity_bucket/2" do
    test "returns 'Last 5 minutes' for very recent activity" do
      now = ~U[2024-01-01 12:05:00Z]
      activity = ~U[2024-01-01 12:03:00Z]
      assert UserResolver.format_activity_bucket(now, activity) == "Last 5 minutes"
    end

    test "returns 'Last hour' for activity within the last hour" do
      now = ~U[2024-01-01 12:00:00Z]
      activity = ~U[2024-01-01 11:15:00Z]
      assert UserResolver.format_activity_bucket(now, activity) == "Last hour"
    end

    test "returns 'Last 24 hours' for activity within the last day" do
      now = ~U[2024-01-01 12:00:00Z]
      activity = ~U[2024-01-01 02:00:00Z]
      assert UserResolver.format_activity_bucket(now, activity) == "Last 24 hours"
    end

    test "returns 'Last 3 days' for activity within 3 days" do
      now = ~U[2024-01-05 12:00:00Z]
      activity = ~U[2024-01-04 00:00:00Z]
      assert UserResolver.format_activity_bucket(now, activity) == "Last 3 days"
    end

    test "returns 'More than 3 days ago' for old activity" do
      now = ~U[2024-01-10 12:00:00Z]
      activity = ~U[2024-01-01 00:00:00Z]
      assert UserResolver.format_activity_bucket(now, activity) == "More than 3 days ago"
    end

    test "boundary: exactly 5 minutes ago still counts as last 5 minutes" do
      now = ~U[2024-01-01 12:05:00Z]
      # Exactly 300 seconds ago — NOT < 300, so should be "Last hour"
      activity = ~U[2024-01-01 12:00:00Z]
      assert UserResolver.format_activity_bucket(now, activity) == "Last hour"
    end
  end

  describe "transform_entities_stats/1" do
    test "maps entity types to named fields" do
      input = %{
        insight: 5,
        chart_configuration: 3,
        query: 2,
        dashboard: 1,
        user_trigger: 4,
        screener: 0,
        project_watchlist: 7,
        address_watchlist: 2
      }

      result = UserResolver.transform_entities_stats(input)

      assert result == %{
               insights_created: 5,
               chart_configurations_created: 3,
               queries_created: 2,
               dashboards_created: 1,
               alerts_created: 4,
               screeners_created: 0,
               project_watchlists_created: 7,
               address_watchlists_created: 2
             }
    end

    test "defaults missing keys to 0" do
      result = UserResolver.transform_entities_stats(%{})

      assert result.insights_created == 0
      assert result.dashboards_created == 0
      assert result.alerts_created == 0
      assert result.queries_created == 0
    end

    test "ignores unknown keys" do
      result = UserResolver.transform_entities_stats(%{unknown_entity: 99, insight: 1})
      assert result.insights_created == 1
      refute Map.has_key?(result, :unknown_entity)
    end
  end
end
