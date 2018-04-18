defmodule Sanbase.ExternalServices.ProjectInfoTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo
  alias Sanbase.Voting.Tag

  test "creating project info from a project" do
    project =
      %Project{
        coinmarketcap_id: "coinmarketcap_id",
        name: "Name",
        website_link: "website.link.com",
        email: "email@link.com",
        reddit_link: "reddit.link.com",
        twitter_link: "twitter.link.com",
        bitcointalk_link: "bitcointalk.link.com",
        blog_link: "blog.link.com",
        github_link: "github.link.com",
        telegram_link: "telegram.link.com",
        slack_link: "slack.link.com",
        facebook_link: "facebook.link.com",
        whitepaper_link: "whitepaper.link.com",
        ticker: "SAN",
        token_decimals: 4,
        total_supply: 50000
      }
      |> Repo.insert!()

    %Ico{project_id: project.id}
    |> Repo.insert!()

    expected_project_info = %ProjectInfo{
      coinmarketcap_id: "coinmarketcap_id",
      name: "Name",
      website_link: "website.link.com",
      email: "email@link.com",
      reddit_link: "reddit.link.com",
      twitter_link: "twitter.link.com",
      bitcointalk_link: "bitcointalk.link.com",
      blog_link: "blog.link.com",
      github_link: "github.link.com",
      telegram_link: "telegram.link.com",
      slack_link: "slack.link.com",
      facebook_link: "facebook.link.com",
      whitepaper_link: "whitepaper.link.com",
      ticker: "SAN",
      token_decimals: 4,
      total_supply: 50000
    }

    assert expected_project_info == ProjectInfo.from_project(project)
  end

  test "updating project info if there is no ico attached to it" do
    project =
      %Project{coinmarketcap_id: "santiment", name: "Santiment"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          coinmarketcap_id: "santiment",
          github_link: "https://github.com/santiment",
          main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
          contract_block_number: 3_972_935,
          token_decimals: 18
        },
        project
      )

    assert project.github_link == "https://github.com/santiment"
    assert project.token_decimals == 18

    assert project.main_contract_address == "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"

    assert Project.initial_ico(project).contract_block_number == 3_972_935
  end

  test "updating project info if there is ico attached to it" do
    project =
      %Project{coinmarketcap_id: "santiment", name: "Santiment"}
      |> Repo.insert!()

    ico =
      %Ico{project_id: project.id}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          coinmarketcap_id: "santiment",
          github_link: "https://github.com/santiment",
          main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
          contract_block_number: 3_972_935
        },
        project
      )

    assert project.github_link == "https://github.com/santiment"
    assert project.main_contract_address == "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    assert Project.initial_ico(project).id == ico.id

    assert Project.initial_ico(project).contract_block_number == 3_972_935
  end

  test "update project_info with new ticker inserts into tags" do
    ticker = "SAN"

    project =
      %Project{coinmarketcap_id: "santiment", name: "Santiment"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          coinmarketcap_id: "santiment",
          ticker: "SAN"
        },
        project
      )

    assert project.ticker == ticker
    assert Tag |> Repo.one() |> Map.get(:name) == ticker
  end

  test "update project_info with ticker - does not insert into tags if duplicate tag" do
    ticker = "SAN"

    %Tag{name: ticker}
    |> Repo.insert!()

    project =
      %Project{coinmarketcap_id: "santiment", name: "Santiment", ticker: "OLD_TICKR"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          coinmarketcap_id: "santiment",
          ticker: "SAN"
        },
        project
      )

    assert project.ticker == ticker
    assert Tag |> Repo.all() |> Enum.count() == 1
  end
end
