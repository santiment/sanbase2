defmodule Sanbase.ExternalServices.Coinmarketcap.ScraperTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.Scraper
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.Model.Project

  test "parsing the project page" do
    project_info =
      File.read!(Path.join(__DIR__, "data/project_page.html"))
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
    ordinary_contract = build(:contract_address)
    third_contract = build(:contract_address)

    project =
      insert(:random_project,
        contract_addresses: [main_contract, ordinary_contract]
      )

    project_info_map = %ProjectInfo{
      slug: "santiment",
      main_contract_address: third_contract.address
    }

    File.read!(Path.join(__DIR__, "data/project_page.html"))
    |> Scraper.parse_project_page(project_info_map)

    assert Enum.find(project.contract_addresses, &(&1.address == third_contract.label != "main"))
  end
end
