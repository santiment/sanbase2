defmodule Sanbase.ExternalServices.Etherscan.ScraperTest do
  use ExUnit.Case

  alias Sanbase.ExternalServices.Etherscan.Scraper
  alias Sanbase.ExternalServices.ProjectInfo

  test "parsing the address page" do
    html = File.read!(Path.join(__DIR__, "address_info_page.html"))

    assert Scraper.parse_address_page!(html, %ProjectInfo{}) == %ProjectInfo{
             creation_transaction:
               "0x83705b4dcaa603d17c2fc642df91b3f7e2f7c2d6fa4844f878602c4f233fe79b"
           }
  end

  test "parsing the token summary page" do
    html = File.read!(Path.join(__DIR__, "token_summary_page.html"))

    assert Scraper.parse_token_page!(html, %ProjectInfo{}) == %ProjectInfo{
             total_supply: 6_804_870_174_878_168_246_198_837_603,
             main_contract_address: "0x744d70fdbe2ba4cf95131626614a1763df805b9e",
             token_decimals: 18,
             website_link: "https://status.im/",
             email: "hello@eosgold.io",
             reddit_link: "https://www.reddit.com/r/statusim/",
             twitter_link: "https://twitter.com/ethstatus",
             bitcointalk_link: "https://bitcointalk.org/index.php?topic=2419283.240",
             blog_link: "https://blog.omisego.network/",
             github_link: "https://github.com/status-im",
             telegram_link: "https://t.me/civicplatform",
             slack_link: "http://slack.status.im/",
             facebook_link: "https://www.facebook.com/ethstatus",
             whitepaper_link: "https://status.im/whitepaper.pdf"
           }
  end
end
