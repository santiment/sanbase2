defmodule Sanbase.Graphql.ProjectApiTest do
  use SanbaseWeb.ConnCase, async: false

  require Sanbase.Utils.Config, as: Config

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Model.Project

  test "fetch funds raised from icos", context do
    currency_eth = insert(:currency, %{code: "ETH"})
    currency_btc = insert(:currency, %{code: "BTC"})
    currency_usd = insert(:currency, %{code: "USD"})

    p1 = insert(:random_project)
    p2 = insert(:random_project)

    ico1_1 = insert(:ico, %{project_id: p1.id})
    ico2_1 = insert(:ico, %{project_id: p2.id})
    ico2_2 = insert(:ico, %{project_id: p2.id})

    insert(:ico_currency, %{ico_id: ico1_1.id, currency_id: currency_usd.id, amount: 123.45})
    insert(:ico_currency, %{ico_id: ico2_1.id, currency_id: currency_usd.id, amount: 100})
    insert(:ico_currency, %{ico_id: ico2_1.id, currency_id: currency_eth.id, amount: 50})
    insert(:ico_currency, %{ico_id: ico2_1.id, currency_id: currency_btc.id, amount: 300})
    insert(:ico_currency, %{ico_id: ico2_2.id, currency_id: currency_usd.id, amount: 200})

    query = """
    {
      project(id:$id) {
        name,
        fundsRaisedIcos {
          amount,
          currencyCode
        }
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post(
        "/graphql",
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{p1.id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => p1.name,
               "fundsRaisedIcos" => [%{"currencyCode" => "USD", "amount" => "123.45"}]
             }

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post(
        "/graphql",
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{p2.id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => p2.name,
               "fundsRaisedIcos" => [
                 %{"currencyCode" => "BTC", "amount" => "300"},
                 %{"currencyCode" => "ETH", "amount" => "50"},
                 %{"currencyCode" => "USD", "amount" => "300"}
               ]
             }
  end

  test "fetch project by coinmarketcap id", context do
    project = insert(:random_project)

    query = """
    {
      projectBySlug(slug: "#{project.coinmarketcap_id}") {
        name
        coinmarketcapId
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    assert result["data"]["projectBySlug"]["name"] == project.name
    assert result["data"]["projectBySlug"]["coinmarketcapId"] == project.coinmarketcap_id
  end

  test "fetch project logos", context do
    project =
      insert(
        :random_project,
        %{
          logo_url: "logo_url.png",
          logo_64_url: "logo_64_url.png",
          logo_32_url: "logo_32_url.png"
        }
      )

    query = """
    {
      projectBySlug(slug: "#{project.coinmarketcap_id}") {
        logo_url
        logo_64_url
        logo_32_url
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    assert result["data"]["projectBySlug"]["logo_url"] == "logo_url.png"
    assert result["data"]["projectBySlug"]["logo_64_url"] == "logo_64_url.png"
    assert result["data"]["projectBySlug"]["logo_32_url"] == "logo_32_url.png"
  end

  test "Fetch project's github links", context do
    project =
      insert(:random_project, %{
        github_organizations: [
          build(:github_organization),
          build(:github_organization),
          build(:github_organization)
        ]
      })

    query = """
    {
      projectBySlug(slug: "#{project.coinmarketcap_id}") {
        githubLinks
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    expected_github_links =
      project.github_organizations
      |> Enum.map(& &1.organization)
      |> Enum.map(&Project.GithubOrganization.organization_to_link/1)
      |> Enum.sort()

    github_links = result["data"]["projectBySlug"]["githubLinks"] |> Enum.sort()
    assert github_links == expected_github_links
  end

  test "fetch non existing project by coinmarketcap id", context do
    cmc_id = "project_does_not_exist_cmc_id"

    query = """
    {
      projectBySlug(slug: "#{cmc_id}") {
        name,
        coinmarketcapId
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    [project_error] = result["errors"]

    assert String.contains?(project_error["message"], "not found")
  end

  test "fetch project ico_price by slug", context do
    project = insert(:random_project)

    insert(:ico, %{project_id: project.id, token_usd_ico_price: Decimal.from_float(0.1)})
    insert(:ico, %{project_id: project.id, token_usd_ico_price: Decimal.from_float(0.2)})
    insert(:ico, %{project_id: project.id, token_usd_ico_price: nil})

    response = query_ico_price(context, project.coinmarketcap_id)

    assert response["icoPrice"] == 0.2
  end

  test "fetch project ico_price when it is nil", context do
    project = insert(:random_project)
    insert(:ico, %{project_id: project.id, token_usd_ico_price: nil})

    response = query_ico_price(context, project.coinmarketcap_id)

    assert response["icoPrice"] == nil
  end

  test "fetch project ico_price when the project does not have ico record", context do
    project = insert(:random_project)

    response = query_ico_price(context, project.coinmarketcap_id)

    assert response["icoPrice"] == nil
  end

  # Helper functions

  defp query_ico_price(context, cmc_id) do
    query = """
    {
      projectBySlug(slug: "#{cmc_id}") {
        icoPrice
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))

    json_response(result, 200)["data"]["projectBySlug"]
  end

  defp get_authorization_header do
    username = context_config(:basic_auth_username)
    password = context_config(:basic_auth_password)

    "Basic " <> Base.encode64(username <> ":" <> password)
  end

  defp context_config(key) do
    Config.module_get(SanbaseWeb.Graphql.ContextPlug, key)
  end
end
