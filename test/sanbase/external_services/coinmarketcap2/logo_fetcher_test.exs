defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcherTest do
  use Sanbase.DataCase

  require Sanbase.Utils.Config, as: Config

  import Sanbase.Factory
  import Tesla.Mock
  import ExUnit.CaptureLog

  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.LogoFetcher
  alias Sanbase.Model.{Project, CmcProject}

  describe "when successful" do
    setup do
      bitcoin = insert(:project, %{ticker: "BTC", coinmarketcap_id: "bitcoin"})
      ethereum = insert(:project, %{ticker: "ETH", coinmarketcap_id: "ethereum"})

      info_url =
        Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
          "v1/cryptocurrency/info?slug=#{bitcoin.coinmarketcap_id},#{ethereum.coinmarketcap_id}"

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

      assert Repo.get(Project, context.bitcoin.id).logo32_url =~
               "/#{context.bitcoin.coinmarketcap_id}.png"

      assert Repo.get(Project, context.ethereum.id).logo64_url =~
               "/#{context.ethereum.coinmarketcap_id}.png"
    end

    test "saves logos uploaded at timestamps", context do
      LogoFetcher.run()

      bitcoin_logo_uploaded_at = CmcProject.by_project_id(context.bitcoin.id).logos_uploaded_at

      ethereum_logo_uploaded_at = CmcProject.by_project_id(context.ethereum.id).logos_uploaded_at

      assert Timex.diff(Timex.now(), bitcoin_logo_uploaded_at, :minutes) < 1
      assert Timex.diff(Timex.now(), ethereum_logo_uploaded_at, :minutes) < 1
    end

    test "saves logo hash", context do
      LogoFetcher.run()

      assert CmcProject.by_project_id(context.bitcoin.id).logo_hash ==
               "480ab7007e9f1b19e932807a96d668508b4ed1b26061a9f1baf98f007f9553be"

      assert CmcProject.by_project_id(context.ethereum.id).logo_hash ==
               "f7b004ff68915bc870fb5f4a9b884fc491e5320e12237e20105b25aaf0ceec23"
    end

    test "will upload new logos when logo hash has changed", context do
      cmc_project = CmcProject.get_or_insert(context.bitcoin.id)

      CmcProject.changeset(
        cmc_project,
        %{logo_hash: "old_image_hash", logos_uploaded_at: Timex.shift(Timex.now(), days: -90)}
      )
      |> Repo.update()

      LogoFetcher.run()

      assert CmcProject.by_project_id(context.bitcoin.id).logo_hash ==
               "480ab7007e9f1b19e932807a96d668508b4ed1b26061a9f1baf98f007f9553be"

      bitcoin_logo_uploaded_at = CmcProject.by_project_id(context.bitcoin.id).logos_uploaded_at
      assert Timex.diff(Timex.now(), bitcoin_logo_uploaded_at, :minutes) < 1
    end
  end

  describe "when unsuccessful" do
    test "can handle invalid logo links" do
      bitcoin = insert(:project, %{ticker: "BTC", coinmarketcap_id: "bitcoin"})

      info_url =
        Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
          "v1/cryptocurrency/info?slug=bitcoin"

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
