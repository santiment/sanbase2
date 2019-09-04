defmodule Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfoTest do
  use Sanbase.DataCase

  require Sanbase.Utils.Config, as: Config

  import Sanbase.Factory
  import Tesla.Mock

  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo

  @moduletag capture_log: true

  test "parses json and returns logo urls" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/cryptocurrency_info.json"))
      }
    end)

    {:ok, data} = CryptocurrencyInfo.fetch_data(["bitcoin", "ethereum"])

    assert Enum.at(data, 0).logo == "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png"
    assert Enum.at(data, 1).logo == "https://s2.coinmarketcap.com/static/img/coins/64x64/1027.png"
  end

  test "returns error when slugs are more than 100" do
    {:error, error} = CryptocurrencyInfo.fetch_data(Enum.to_list(0..100))

    assert error == """
           Accepting over 100 slugs will most probably result in very long URL.
           URLs over 2,000 characters are considered problematic.
           """
  end

  test "can handle invalid slugs" do
    insert(:project, %{ticker: "BTC", slug: "bitcoin"})
    insert(:project, %{ticker: "ETH", slug: "ethereum"})
    insert(:project, %{ticker: "INV0", slug: "invalid0"})
    insert(:project, %{ticker: "INV1", slug: "invalid1"})

    url_with_invalid_slugs =
      Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
        "v1/cryptocurrency/info?slug=bitcoin,ethereum,invalid0,invalid1"

    url_with_cleaned_slugs =
      Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
        "v1/cryptocurrency/info?slug=bitcoin,ethereum"

    mock(fn
      %{method: :get, url: ^url_with_invalid_slugs} ->
        %Tesla.Env{
          status: 400,
          body:
            Jason.encode!(%{
              status: %{
                timestamp: "2019-07-15T09:09:55.761Z",
                error_code: 400,
                error_message: "Invalid values for \"slug\": \"invalid0,invalid1\"",
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

    {:ok, data} = CryptocurrencyInfo.fetch_data(["bitcoin", "ethereum", "invalid0", "invalid1"])

    assert Enum.map(data, & &1.slug) == ["bitcoin", "ethereum"]
  end
end
