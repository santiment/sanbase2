defmodule SanbaseWeb.Graphql.ProjectApiGetQueriesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.Post

  setup do
    infr_eth = insert(:infrastructure, %{code: "ETH"})
    infr_btc = insert(:infrastructure, %{code: "BTC"})

    # ERC20
    p1 = insert(:random_project, %{ticker: "BTC", infrastructure_id: infr_eth.id})
    insert(:ico, %{project_id: p1.id})

    # Not ERC20 because of no contract
    p2 =
      insert(:random_project, %{
        ticker: "BTC",
        infrastructure_id: infr_eth.id,
        contract_addresses: []
      })

    insert(:ico, %{project_id: p2.id})

    # Should be classified as currency despite having main contract address
    p3 = insert(:random_project, %{infrastructure_id: infr_btc.id, ticker: rand_str(4)})
    insert(:ico, %{project_id: p3.id})

    {:ok, project1: p1, project2: p2, project3: p3}
  end

  test "fetch all projects", context do
    query = """
    {
      allProjects{
        name
      }
    }
    """

    result = post(context.conn, "/graphql", query_skeleton(query, "allProjects"))

    projects = json_response(result, 200)["data"]["allProjects"]

    assert %{"name" => context.project1.name} in projects
    assert %{"name" => context.project2.name} in projects
    assert %{"name" => context.project3.name} in projects
  end

  test "fetch all erc20 projects", context do
    query = """
    {
      allErc20Projects {
        name
      }
    }
    """

    result = post(context.conn, "/graphql", query_skeleton(query, "allErc20Projects"))

    projects = json_response(result, 200)["data"]["allErc20Projects"]

    assert %{"name" => context.project1.name} in projects
    assert %{"name" => context.project2.name} not in projects
    assert %{"name" => context.project3.name} not in projects
  end

  test "fetch all currency projects", context do
    query = """
    {
      allCurrencyProjects {
        name
      }
    }
    """

    result = post(context.conn, "/graphql", query_skeleton(query, "allCurrencyProjects"))

    projects = json_response(result, 200)["data"]["allCurrencyProjects"]

    assert %{"name" => context.project1.name} not in projects
    assert %{"name" => context.project2.name} in projects
    assert %{"name" => context.project3.name} in projects
  end

  test "fetch all projects by ticker", context do
    query = """
    {
      allProjectsByTicker(ticker: "BTC") {
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allProjectsByTicker"))
      |> json_response(200)

    projects = result["data"]["allProjectsByTicker"]

    assert %{"name" => context.project1.name} in projects
    assert %{"name" => context.project2.name} in projects
  end

  test "fetch all projects with their insights", context do
    post_title = "Awesome post"
    tag = insert(:tag, %{name: context.project1.ticker})
    user = insert(:user)

    insert(:post,
      title: post_title,
      user: user,
      tags: [tag],
      state: Post.approved_state(),
      ready_state: Post.published()
    )

    query = """
    {
      allProjects{
        ticker,
        related_posts {
          title
        }
      }
    }
    """

    result = post(context.conn, "/graphql", query_skeleton(query, "allProjects"))

    projects = json_response(result, 200)["data"]["allProjects"]

    assert %{
             "ticker" => context.project1.ticker,
             "related_posts" => [%{"title" => post_title}]
           } in projects
  end
end
