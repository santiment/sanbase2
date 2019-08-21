defmodule SanbaseWeb.Graphql.ProjectApiSocialVolumeQuery do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Model.Project

  test "default query contains project name, slug and ticker", %{conn: conn} do
    p1 = insert(:random_erc20_project)
    query = Project.SocialVolumeQuery.default_query(p1)
    assert String.contains?(query, p1.ticker)
    assert String.contains?(query, p1.name)
    assert String.contains?(query, p1.coinmarketcap_id)
    assert String.contains?(query, "OR")
  end
end
