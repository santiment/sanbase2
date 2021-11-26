defmodule SanbaseWeb.Graphql.ProjectApiTest do
  use SanbaseWeb.ConnCase, async: false

  require Sanbase.Utils.Config, as: Config

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Model.Project

  test "projects by function for traded on exchanges", context do
    [p1, p2, p3, p4] = projects = for _ <- 1..4, do: insert(:random_project)

    for p <- projects do
      insert(:source_slug_mapping, source: "cryptocompare", slug: p.ticker, project_id: p.id)
    end

    pairs = [
      {p1, "Binance"},
      {p2, "Binance"},
      {p2, "LFinance"},
      {p3, "Binance"},
      {p3, "Bitfinex"},
      {p3, "Uniswap"},
      {p4, "Bitfinex"},
      {p4, "LFinance"}
    ]

    for {p, exchange} <- pairs, do: insert(:market, base_asset: p.ticker, exchange: exchange)

    query = """
    {
      allProjects{
        slug
        tradedOnExchanges
        tradedOnExchangesCount
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "allProjects"])

    assert %{
             "slug" => p1.slug,
             "tradedOnExchanges" => ["Binance"],
             "tradedOnExchangesCount" => 1
           } in result

    assert %{
             "slug" => p2.slug,
             "tradedOnExchanges" => ["Binance", "LFinance"],
             "tradedOnExchangesCount" => 2
           } in result

    assert %{
             "slug" => p3.slug,
             "tradedOnExchanges" => ["Binance", "Bitfinex", "Uniswap"],
             "tradedOnExchangesCount" => 3
           } in result

    assert %{
             "slug" => p4.slug,
             "tradedOnExchanges" => ["Bitfinex", "LFinance"],
             "tradedOnExchangesCount" => 2
           } in result
  end

  test "fetch market segments and tags for projects", context do
    ms1 = insert(:market_segment, name: "Ethereum", type: "Infrastructure")
    ms2 = insert(:market_segment, name: "DeFi", type: "Financial")
    p1 = insert(:random_project, market_segments: [ms1])
    p2 = insert(:random_project, market_segments: [ms1])
    p3 = insert(:random_project, market_segments: [ms2])

    query = """
    {
      allProjects{
        slug
        marketSegments
        tags { name type }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "allProjects"])

    assert %{
             "marketSegments" => ["Ethereum"],
             "slug" => p1.slug,
             "tags" => [%{"name" => "Ethereum", "type" => "Infrastructure"}]
           } in result

    assert %{
             "marketSegments" => ["Ethereum"],
             "slug" => p2.slug,
             "tags" => [%{"name" => "Ethereum", "type" => "Infrastructure"}]
           } in result

    assert %{
             "marketSegments" => ["DeFi"],
             "slug" => p3.slug,
             "tags" => [%{"name" => "DeFi", "type" => "Financial"}]
           } in result
  end

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
      projectBySlug(slug: "#{project.slug}") {
        name
        slug
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    assert result["data"]["projectBySlug"]["name"] == project.name
    assert result["data"]["projectBySlug"]["slug"] == project.slug
  end

  test "fetch project logos", context do
    project =
      insert(
        :random_project,
        %{logo_url: "logo_url.png"}
      )

    query = """
    {
      projectBySlug(slug: "#{project.slug}") {
        logoUrl
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    assert result["data"]["projectBySlug"]["logoUrl"] == "logo_url.png"
  end

  test "fetch project dark logos", context do
    project =
      insert(
        :random_project,
        %{dark_logo_url: "dark_logo_url.png"}
      )

    query = """
    {
      projectBySlug(slug: "#{project.slug}") {
        darkLogoUrl
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))
      |> json_response(200)

    assert result["data"]["projectBySlug"]["darkLogoUrl"] == "dark_logo_url.png"
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
      projectBySlug(slug: "#{project.slug}") {
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
        slug
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

    response = query_ico_price(context, project.slug)

    assert response["icoPrice"] == 0.2
  end

  test "fetch project ico_price when it is nil", context do
    project = insert(:random_project)
    insert(:ico, %{project_id: project.id, token_usd_ico_price: nil})

    response = query_ico_price(context, project.slug)

    assert response["icoPrice"] == nil
  end

  test "fetch project ico_price when the project does not have ico record", context do
    project = insert(:random_project)

    response = query_ico_price(context, project.slug)

    assert response["icoPrice"] == nil
  end

  test "fetch social media links", context do
    random_string = rand_str()

    project =
      insert(
        :random_project,
        %{
          discord_link: "https://discord.gg/#{random_string}",
          twitter_link: "https://twitter.com/#{random_string}",
          slack_link: "https://#{random_string}.slack.com",
          facebook_link: "https://facebook.com/#{random_string}",
          reddit_link: "https://reddit.com/r/#{random_string}"
        }
      )

    query = """
    {
      projectBySlug(slug: "#{project.slug}") {
        discordLink
        twitterLink
        slackLink
        facebookLink
        redditLink
      }
    }
    """

    result = execute_query(context.conn, query, "projectBySlug")

    assert %{
             "discordLink" => "https://discord.gg/#{random_string}",
             "twitterLink" => "https://twitter.com/#{random_string}",
             "slackLink" => "https://#{random_string}.slack.com",
             "facebookLink" => "https://facebook.com/#{random_string}",
             "redditLink" => "https://reddit.com/r/#{random_string}"
           } == result
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
    username = Config.module_get(SanbaseWeb.Graphql.AuthPlug, :basic_auth_username)
    password = Config.module_get(SanbaseWeb.Graphql.AuthPlug, :basic_auth_password)

    "Basic " <> Base.encode64(username <> ":" <> password)
  end
end
