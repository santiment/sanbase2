defmodule Sanbase.ExternalServices.Coinmarketcap.ScraperTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.Scraper
  alias Sanbase.ExternalServices.ProjectInfo

  test "parsing the project page" do
    project_info =
      __DIR__
      |> Path.join("data/project_page.html")
      |> File.read!()
      |> Scraper.parse_project_page(%ProjectInfo{slug: "santiment"})

    assert project_info == %ProjectInfo{
             slug: "santiment",
             name: "Santiment Network Token",
             ticker: "SAN",
             website_link: "https://santiment.net/",
             github_link: "https://github.com/santiment",
             main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
             etherscan_token_name: "SAN"
           }
  end

  test "scraping a project with a main contract doesn't make the new contract main" do
    main_contract = build(:contract_address, label: "main")
    second_contract = build(:contract_address)

    project =
      insert(:random_project,
        contract_addresses: [main_contract]
      )

    project_info_map = %ProjectInfo{
      slug: project.slug,
      main_contract_address: second_contract.address
    }

    project_info =
      __DIR__
      |> Path.join("data/project_page.html")
      |> File.read!()
      |> Scraper.parse_project_page(project_info_map)

    {:ok, project} =
      ProjectInfo.update_project(
        project_info,
        project
      )

    assert length(project.contract_addresses) == 2

    contract1 = Enum.find(project.contract_addresses, &(&1.address == main_contract.address))
    contract2 = Enum.find(project.contract_addresses, &(&1.address == second_contract.address))

    assert contract1.label == "main"
    assert contract2.label != "main"
  end
end
