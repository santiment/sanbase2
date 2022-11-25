defmodule SanbaseWeb.Graphql.ProjectApiSocialVolumeQuery do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Project

  test "default query contains lowercased project name, slug and ticker" do
    p1 = insert(:random_erc20_project)
    query = Project.SocialVolumeQuery.default_query(p1)
    assert String.contains?(query, String.downcase(p1.ticker))
    assert String.contains?(query, String.downcase(p1.name))
    assert String.contains?(query, String.downcase(p1.slug))
    assert String.contains?(query, "OR")
  end
end
