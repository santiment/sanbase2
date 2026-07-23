defmodule Sanbase.Clickhouse.GithubActivityStatsQueryTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Clickhouse.Github.SqlQuery, only: [github_activity_stats_query: 4]

  @from ~U[2024-04-01 00:00:00Z]
  @to ~U[2024-05-01 00:00:00Z]

  test "owners and slugs are passed as parallel lists" do
    pairs = [{"Org1", "slug-a"}, {"org2", "slug-a"}, {"org3", "slug-b"}]

    query = github_activity_stats_query(pairs, @from, @to, [])

    assert query.parameters[:owners] == ["org1", "org2", "org3"]
    assert query.parameters[:slugs] == ["slug-a", "slug-a", "slug-b"]
    assert query.parameters[:from] == DateTime.to_unix(@from)
    assert query.parameters[:to] == DateTime.to_unix(@to)

    assert query.sql =~ "transform(owner, {{owners}}, {{slugs}}, '') AS slug"
    assert query.sql =~ "GROUP BY slug"
    refute query.sql =~ "ORDER BY"
    refute query.sql =~ "LIMIT"
  end

  test "order_by option" do
    pairs = [{"org1", "slug-a"}]

    query = github_activity_stats_query(pairs, @from, @to, order_by: :github_activity)

    assert query.sql =~ "ORDER BY github_activity DESC"

    query = github_activity_stats_query(pairs, @from, @to, order_by: :dev_activity)

    assert query.sql =~ "ORDER BY dev_activity DESC"
  end

  test "bots are identified by the [bot] suffix" do
    query = github_activity_stats_query([{"org1", "slug-a"}], @from, @to, [])

    assert query.sql =~ "endsWith(actor, '[bot]')"
  end
end
