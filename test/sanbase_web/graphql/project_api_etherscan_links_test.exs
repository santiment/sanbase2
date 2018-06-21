defmodule SanbaseWeb.Graphql.ProjecApiEtherscanLinksTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.ExternalServices.Etherscan.Store
  alias Sanbase.Model.{Project, Ico, LatestCoinmarketcapData}
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"

    Store.drop_measurement(ticker)

    project =
      %Project{
        coinmarketcap_id: "coinmarketcap_id",
        name: "Name",
        website_link: "website.link.com",
        email: "email@link.com",
        reddit_link: "reddit.link.com",
        twitter_link: "twitter.link.com",
        btt_link: "bitcointalk.link.com",
        blog_link: "blog.link.com",
        github_link: "github.link.com",
        telegram_link: "telegram.link.com",
        slack_link: "slack.link.com",
        facebook_link: "facebook.link.com",
        whitepaper_link: "whitepaper.link.com",
        ticker: ticker,
        token_decimals: 4
      }
      |> Repo.insert!()

    %Ico{project_id: project.id}
    |> Repo.insert!()

    %LatestCoinmarketcapData{
      coinmarketcap_id: project.coinmarketcap_id,
      total_supply: 5000,
      update_time: Ecto.DateTime.utc()
    }
    |> Repo.insert!()

    [
      project: project,
      ticker: ticker
    ]
  end

  test "project total eth spent whole interval", context do
    expected_project = %{
      "coinmarketcap_id" => "coinmarketcap_id",
      "name" => "Name",
      "website_link" => "website.link.com",
      "email" => "email@link.com",
      "reddit_link" => "reddit.link.com",
      "twitter_link" => "twitter.link.com",
      "btt_link" => "bitcointalk.link.com",
      "blog_link" => "blog.link.com",
      "github_link" => "github.link.com",
      "telegram_link" => "telegram.link.com",
      "slack_link" => "slack.link.com",
      "facebook_link" => "facebook.link.com",
      "whitepaper_link" => "whitepaper.link.com",
      "ticker" => context.ticker,
      "token_decimals" => 4,
      "total_supply" => "5000"
    }

    query = """
    {
      project(id: #{context.project.id}) {
        coinmarketcap_id
        name
        website_link
        email
        reddit_link
        twitter_link
        btt_link
        blog_link
        github_link
        telegram_link
        slack_link
        facebook_link
        whitepaper_link
        ticker
        token_decimals
        total_supply
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    project = json_response(result, 200)["data"]["project"]

    assert project == expected_project
  end
end
