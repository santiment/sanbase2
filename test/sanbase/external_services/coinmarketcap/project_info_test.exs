defmodule Sanbase.ExternalServices.Coinmarketcap.ProjectInfoTest do
  use ExUnit.Case

  alias Sanbase.ExternalServices.Coinmarketcap.ProjectInfo

  test "parsing the project page" do
    html = File.read!(Path.join(__DIR__, "project_page.html"))

    assert ProjectInfo.scrape_info("santiment", html) == %ProjectInfo{
      coinmarketcap_id: "santiment",
      name: "Santiment Network Token",
      ticker: "SAN",
      website_link: "https://santiment.net/",
      github_link: "https://github.com/santiment",
      smart_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    }
  end
end
