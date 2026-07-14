defmodule Sanbase.ExternalServices.ProjectInfoTest do
  use Sanbase.DataCase, async: true

  import ExUnit.CaptureLog
  import Mock
  import Sanbase.Factory

  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Project
  alias Sanbase.Model.Ico
  alias Sanbase.Repo
  alias Sanbase.Tag

  test "creating project info from a project" do
    project =
      %Project{
        slug: "slug",
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
        ticker: "SAN",
        token_decimals: 4,
        total_supply: 50_000
      }
      |> Repo.insert!()

    %Ico{project_id: project.id}
    |> Repo.insert!()

    expected_project_info = %ProjectInfo{
      slug: "slug",
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
      ticker: "SAN",
      token_decimals: 4,
      total_supply: 50_000
    }

    assert expected_project_info == ProjectInfo.from_project(project)
  end

  test "updating project info if there is no ico attached to it" do
    project =
      %Project{slug: "santiment", name: "Santiment"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
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
      %Project{slug: "santiment", name: "Santiment"}
      |> Repo.insert!()

    ico =
      %Ico{project_id: project.id}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
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
      %Project{slug: "santiment", name: "Santiment"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
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
      %Project{slug: "santiment", name: "Santiment", ticker: "OLD_TICKR"}
      |> Repo.insert!()

    assert capture_log(fn ->
             ProjectInfo.update_project(
               %ProjectInfo{
                 name: "Santiment",
                 slug: "santiment",
                 ticker: "SAN"
               },
               project
             )
           end) =~ "has already been taken"
  end

  test "from_project sets the infrastructure code" do
    project = insert(:random_erc20_project)

    assert ProjectInfo.from_project(project).infrastructure_code == "ETH"
  end

  test "fetch_from_ethereum_node fetches data for ethereum contracts" do
    project_info = %ProjectInfo{
      slug: "santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
      infrastructure_code: "ETH"
    }

    Sanbase.Mock.prepare_mock2(&Ethauth.total_supply/1, {:ok, 83_000_000})
    |> Sanbase.Mock.prepare_mock2(&Ethauth.token_decimals/1, {:ok, 18})
    |> Sanbase.Mock.run_with_mocks(fn ->
      project_info = ProjectInfo.fetch_from_ethereum_node(project_info)

      assert project_info.total_supply == 83_000_000
      assert project_info.token_decimals == 18
    end)
  end

  test "fetch_from_ethereum_node fetches data when the infrastructure is not set" do
    project_info = %ProjectInfo{
      slug: "santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
      infrastructure_code: nil
    }

    Sanbase.Mock.prepare_mock2(&Ethauth.total_supply/1, {:ok, 83_000_000})
    |> Sanbase.Mock.prepare_mock2(&Ethauth.token_decimals/1, {:ok, 18})
    |> Sanbase.Mock.run_with_mocks(fn ->
      project_info = ProjectInfo.fetch_from_ethereum_node(project_info)

      assert project_info.total_supply == 83_000_000
      assert project_info.token_decimals == 18
    end)
  end

  test "fetch_from_ethereum_node skips contracts that are not ethereum addresses" do
    project_info = %ProjectInfo{
      slug: "some-solana-project",
      main_contract_address: "HNg5PYJmtqcmzXrv6S9zP1CDKk5BgDuyFBxbvNApump",
      infrastructure_code: nil
    }

    Sanbase.Mock.prepare_mock2(&Ethauth.total_supply/1, {:ok, 83_000_000})
    |> Sanbase.Mock.prepare_mock2(&Ethauth.token_decimals/1, {:ok, 18})
    |> Sanbase.Mock.run_with_mocks(fn ->
      log =
        capture_log(fn ->
          assert ProjectInfo.fetch_from_ethereum_node(project_info) == project_info
        end)

      assert log =~ "Skip fetching on-chain data for some-solana-project"
      assert_not_called(Ethauth.total_supply(:_))
      assert_not_called(Ethauth.token_decimals(:_))
    end)
  end

  test "fetch_from_ethereum_node skips contracts on non-ethereum infrastructure" do
    project_info = %ProjectInfo{
      slug: "some-bnb-project",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
      infrastructure_code: "BNB"
    }

    Sanbase.Mock.prepare_mock2(&Ethauth.total_supply/1, {:ok, 83_000_000})
    |> Sanbase.Mock.prepare_mock2(&Ethauth.token_decimals/1, {:ok, 18})
    |> Sanbase.Mock.run_with_mocks(fn ->
      log =
        capture_log(fn ->
          assert ProjectInfo.fetch_from_ethereum_node(project_info) == project_info
        end)

      assert log =~ "Skip fetching on-chain data for some-bnb-project"
      assert_not_called(Ethauth.total_supply(:_))
      assert_not_called(Ethauth.token_decimals(:_))
    end)
  end

  test "updating the project info of a project with a contract address" do
    first_contract = build(:contract_address, address: "0xCURRENT", label: "main")
    second_contract = build(:contract_address, address: "0xNEW")

    project = insert(:random_project, contract_addresses: [first_contract])

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
          main_contract_address: second_contract.address
        },
        project
      )

    assert length(project.contract_addresses) == 2

    contract1 = Enum.find(project.contract_addresses, &(&1.address == first_contract.address))
    contract2 = Enum.find(project.contract_addresses, &(&1.address == second_contract.address))

    assert contract1.label == "main"
    assert contract2.label != "main"
  end
end
