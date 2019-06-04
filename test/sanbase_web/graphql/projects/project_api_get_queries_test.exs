defmodule Sanbase.Graphql.ProjectApiGetQueriesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Tag
  alias Sanbase.Insight.{Poll, Post}
  alias Sanbase.Auth.User

  alias Sanbase.Repo

  setup do
    infr_eth = insert(:infrastructure, %{code: "ETH"})

    infr_btc = insert(:infrastructure, %{code: "BTC"})

    p1 =
      insert(:project, %{
        name: rand_str(),
        coinmarketcap_id: rand_str(),
        ticker: rand_str(4),
        main_contract_address: "0x123123",
        infrastructure_id: infr_eth.id
      })

    insert(:ico, %{project_id: p1.id})

    p2 =
      insert(:project, %{
        name: rand_str(),
        coinmarketcap_id: rand_str(),
        ticker: rand_str(4),
        infrastructure_id: infr_eth.id
      })

    insert(:ico, %{project_id: p2.id})

    # Should be classified as currency despite having main contract address
    p3 =
      insert(:project, %{
        name: rand_str(),
        coinmarketcap_id: rand_str(),
        infrastructure_id: infr_btc.id,
        ticker: rand_str(4),
        main_contract_address: "0x1234567890"
      })

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

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allProjects"))

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

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allErc20Projects"))

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

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))

    projects = json_response(result, 200)["data"]["allCurrencyProjects"]

    assert %{"name" => context.project1.name} not in projects
    assert %{"name" => context.project2.name} in projects
    assert %{"name" => context.project3.name} in projects
  end

  test "fetch all projects with their insights", context do
    post_title = "Awesome post"
    tag = Repo.insert!(%Tag{name: context.project1.ticker})
    user = Repo.insert!(%User{salt: User.generate_salt(), privacy_policy_accepted: true})
    poll = Poll.find_or_insert_current_poll!()

    Repo.insert!(%Post{
      title: post_title,
      poll_id: poll.id,
      user_id: user.id,
      tags: [tag]
    })

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

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allProjects"))

    projects = json_response(result, 200)["data"]["allProjects"]

    assert %{
             "ticker" => context.project1.ticker,
             "related_posts" => [%{"title" => post_title}]
           } in projects
  end
end
