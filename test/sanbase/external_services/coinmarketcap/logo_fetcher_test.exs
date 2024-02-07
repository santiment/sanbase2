defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcherTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Tesla.Mock
  import ExUnit.CaptureLog

  alias Sanbase.Repo
  alias Sanbase.Project
  alias Sanbase.ExternalServices.Coinmarketcap.LogoFetcher
  alias Sanbase.Model.LatestCoinmarketcapData

  alias Sanbase.Utils.Config

  describe "when successful" do
    setup do
      bitcoin = insert(:project, %{ticker: "BTC", slug: "bitcoin"})
      ethereum = insert(:project, %{ticker: "ETH", slug: "ethereum"})

      info_url =
        Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
          "v2/cryptocurrency/info?slug=#{bitcoin.slug},#{ethereum.slug}"

      mock(fn
        %{method: :get, url: ^info_url} ->
          %Tesla.Env{
            status: 200,
            body: File.read!(Path.join(__DIR__, "data/cryptocurrency_info.json"))
          }

        %{method: :get, url: "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png"} ->
          %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "data/1.png"))}

        %{method: :get, url: "https://s2.coinmarketcap.com/static/img/coins/64x64/1027.png"} ->
          %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "data/1027.png"))}
      end)

      [bitcoin: bitcoin, ethereum: ethereum]
    end

    test "updates local projects with fetched logos", context do
      LogoFetcher.run()

      file_store_path = "/tmp/sanbase/filestore-test"

      assert Repo.get(Project, context.ethereum.id).logo_url =~
               "#{file_store_path}/logo64_#{context.ethereum.slug}.png"
    end

    test "saves logo hash", context do
      LogoFetcher.run()

      latest_bitcoin_cmc_data = LatestCoinmarketcapData.by_coinmarketcap_id(context.bitcoin.slug)

      latest_ethereum_cmc_data =
        LatestCoinmarketcapData.by_coinmarketcap_id(context.ethereum.slug)

      assert latest_bitcoin_cmc_data.logo_hash ==
               "480ab7007e9f1b19e932807a96d668508b4ed1b26061a9f1baf98f007f9553be"

      assert latest_ethereum_cmc_data.logo_hash ==
               "f7b004ff68915bc870fb5f4a9b884fc491e5320e12237e20105b25aaf0ceec23"
    end

    test "will upload new logos when logo hash has changed", context do
      insert(:latest_cmc_data, %{
        coinmarketcap_id: context.bitcoin.slug,
        logo_hash: "old_file_hash",
        logo_updated_at: Timex.shift(Timex.now(), days: -1)
      })

      LogoFetcher.run()

      assert LatestCoinmarketcapData.get_or_build(context.bitcoin.slug).logo_hash ==
               "480ab7007e9f1b19e932807a96d668508b4ed1b26061a9f1baf98f007f9553be"
    end
  end

  describe "when unsuccessful" do
    test "can handle invalid logo links" do
      bitcoin = insert(:project, %{ticker: "BTC", slug: "bitcoin"})

      info_url =
        Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
          "v2/cryptocurrency/info?slug=bitcoin"

      mock(fn
        %{
          method: :get,
          url: ^info_url
        } ->
          %Tesla.Env{
            status: 200,
            body: File.read!(Path.join(__DIR__, "data/invalid_cryptocurrency_info.json"))
          }

        %{method: :get, url: "http://invalid"} ->
          %Tesla.Env{status: 404, body: "Nothing here"}
      end)

      assert capture_log(fn ->
               LogoFetcher.run()
             end) =~ "Failed downloading logo: http://invalid. Status: 404"

      assert Repo.get(Project, bitcoin.id).logo_url == nil
    end
  end
end
