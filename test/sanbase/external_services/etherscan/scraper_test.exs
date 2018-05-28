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

    assert Scraper.parse_token_page!(html, %ProjectInfo{
             btt_link: "should_not_be_changed_to_nil"
           }) == %ProjectInfo{
             total_supply: 6_804_870_175,
             main_contract_address: "0x744d70fdbe2ba4cf95131626614a1763df805b9e",
             token_decimals: 18,
             website_link: "https://status.im/",
             email: nil,
             reddit_link: "https://www.reddit.com/r/statusim/",
             twitter_link: "https://twitter.com/ethstatus",
             btt_link: "should_not_be_changed_to_nil",
             blog_link: nil,
             github_link: "https://github.com/status-im",
             telegram_link: nil,
             slack_link: "http://slack.status.im/",
             facebook_link: "https://www.facebook.com/ethstatus",
             whitepaper_link: "https://status.im/whitepaper.pdf"
           }
  end
end
