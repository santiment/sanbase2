defmodule Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfoTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Tesla.Mock

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo
  alias Sanbase.Utils.Config

  @moduletag capture_log: true

  test "parses json and returns logo urls" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/cryptocurrency_info.json"))
      }
    end)

    bitcoin = insert(:project, %{slug: "bitcoin"})
    ethereum = insert(:project, %{slug: "ethereum"})
    {:ok, data} = CryptocurrencyInfo.fetch_data([bitcoin, ethereum])

    assert Enum.at(data, 0).logo == "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png"
    assert Enum.at(data, 1).logo == "https://s2.coinmarketcap.com/static/img/coins/64x64/1027.png"
  end

  test "returns error when projects are more than 100" do
    {:error, error} = CryptocurrencyInfo.fetch_data(Enum.to_list(0..100))

    assert error == """
           Accepting over 100 projects will most probably result in very long URL.
           URLs over 2,000 characters are considered problematic.
           """
  end

  test "can handle invalid slugs" do
    p1 = insert(:project, %{ticker: "BTC", slug: "bitcoin"})
    p2 = insert(:project, %{ticker: "ETH", slug: "ethereum"})
    p3 = insert(:project, %{ticker: "INV0", slug: "invalid0"})
    p4 = insert(:project, %{ticker: "INV1", slug: "invalid1"})

    url_with_invalid_slugs =
      Config.module_get(Coinmarketcap, :api_url) <>
        "v2/cryptocurrency/info?slug=bitcoin,ethereum,invalid0,invalid1"

    url_with_cleaned_slugs =
      Config.module_get(Coinmarketcap, :api_url) <>
        "v2/cryptocurrency/info?slug=bitcoin,ethereum"

    mock(fn
      %{method: :get, url: ^url_with_invalid_slugs} ->
        %Tesla.Env{
          status: 400,
          body:
            Jason.encode!(%{
              status: %{
                timestamp: "2019-07-15T09:09:55.761Z",
                error_code: 400,
                error_message: ~s(Invalid values for "slug": "invalid0,invalid1"),
                credit_count: 0
              }
            })
        }

      %{method: :get, url: ^url_with_cleaned_slugs} ->
        %Tesla.Env{
          status: 200,
          body: File.read!(Path.join(__DIR__, "data/cryptocurrency_info.json"))
        }
    end)

    {:ok, data} = CryptocurrencyInfo.fetch_data([p1, p2, p3, p4])

    assert Enum.map(data, & &1.slug) == ["bitcoin", "ethereum"]
  end
end
