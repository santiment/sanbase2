defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcherTest do
  use ExUnit.Case
  use Sanbase.DataCase, async: true

  require Sanbase.Utils.Config, as: Config

  import Sanbase.Factory
  import Tesla.Mock
  import ExUnit.CaptureLog

  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.LogoFetcher, as: LogoFetcher
  alias Sanbase.Model.{Project}

  test "updates local projects with fetched logos" do
    bitcoin = insert(:project, %{ticker: "BTC", coinmarketcap_id: "bitcoin"})
    ethereum = insert(:project, %{ticker: "ETH", coinmarketcap_id: "ethereum"})

    info_url =
      Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
        "v1/cryptocurrency/info?slug=bitcoin,ethereum"

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

    LogoFetcher.run([bitcoin, ethereum])

    assert Repo.get(Project, bitcoin.id).logo_32_url ==
             "/tmp/sanbase/filestore-test/logo_bitcoin.png"

    assert Repo.get(Project, ethereum.id).logo_64_url ==
             "/tmp/sanbase/filestore-test/logo_ethereum.png"
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
             LogoFetcher.run([bitcoin])
           end) =~ "Failed downloading logo: http://invalid. Status: 404"

    assert Repo.get(Project, bitcoin.id).logo_url == nil
  end
end
