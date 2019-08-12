defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcherTest do
  use Sanbase.DataCase

  require Sanbase.Utils.Config, as: Config

  import Sanbase.Factory
  import Tesla.Mock
  import ExUnit.CaptureLog

  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.LogoFetcher
  alias Sanbase.Model.{Project}

  test "updates local projects with fetched logos" do
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

    LogoFetcher.run()

    file_store_path = "/tmp/sanbase/filestore-test"

    assert Repo.get(Project, bitcoin.id).logo32_url =~
             "#{file_store_path}/logo32_#{bitcoin.coinmarketcap_id}.png"

    assert Repo.get(Project, ethereum.id).logo64_url =~
             "#{file_store_path}/logo64_#{ethereum.coinmarketcap_id}.png"
  end

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
