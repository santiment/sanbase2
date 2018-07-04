defmodule Sanbase.Graphql.ProjectApiGetQueriesTest do
  use SanbaseWeb.ConnCase, async: false

  require Sanbase.Utils.Config

  alias Sanbase.Model.{
    Project,
    Infrastructure,
    Ico
  }

  alias Sanbase.Voting.{Poll, Post, Tag}
  alias Sanbase.Auth.User

  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    infr_eth =
      %Infrastructure{}
      |> Infrastructure.changeset(%{code: "ETH"})
      |> Repo.insert!()

    infr_btc =
      %Infrastructure{}
      |> Infrastructure.changeset(%{code: "BTC"})
      |> Repo.insert!()

    project1 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ1",
        name: "Project1",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj1",
        main_contract_address: "0x123123"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project1.id})
    |> Repo.insert!()

    project2 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ2",
        name: "Project2",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj2"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project2.id})
    |> Repo.insert!()

    # Should be classified as currency despite having main contract address
    project3 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ3",
        name: "Project3",
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: "proj3",
        main_contract_address: "0x1234567890"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project3.id})
    |> Repo.insert!()

    {:ok, project: project1}
  end

  test "fetch all projects", context do
    query = """
    {
      allProjects{
        name,
        slug
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allProjects"))

    projects = json_response(result, 200)["data"]["allProjects"]

    assert %{"name" => "Project1", "slug" => "proj1"} in projects
    assert %{"name" => "Project2", "slug" => "proj2"} in projects
    assert %{"name" => "Project3", "slug" => "proj3"} in projects
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

    assert %{"name" => "Project1"} in projects
    assert %{"name" => "Project2"} not in projects
    assert %{"name" => "Project3"} not in projects
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

    assert %{"name" => "Project1"} not in projects
    assert %{"name" => "Project2"} in projects
    assert %{"name" => "Project3"} in projects
  end

  test "fetch all projects with their insights", context do
    post_title = "Awesome post"
    tag = Repo.insert!(%Tag{name: context.project.ticker})
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
             "ticker" => "PRJ1",
             "related_posts" => [%{"title" => post_title}]
           } in projects
  end
end
