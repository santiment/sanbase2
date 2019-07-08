defmodule Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfoTest do
  use ExUnit.Case
  use Sanbase.DataCase, async: true

  require Sanbase.Utils.Config, as: Config

  import Sanbase.Factory
  import Tesla.Mock

  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo, as: CryptocurrencyInfo

  test "parsing the json" do
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

  test "can handle invalid slugs" do
    bitcoin = insert(:project, %{ticker: "BTC", coinmarketcap_id: "bitcoin"})
    invalid0 = insert(:project, %{ticker: "INV0", coinmarketcap_id: "invalid0"})
    invalid1 = insert(:project, %{ticker: "INV1", coinmarketcap_id: "invalid1"})

    url_with_invalid_slugs =
      Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
        "v1/cryptocurrency/info?slug=bitcoin,invalid0,invalid1"

    url_with_cleaned_slugs =
      Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url) <>
        "v1/cryptocurrency/info?slug=bitcoin"

    json_error =
      Jason.encode!(%{
        status: %{
          timestamp: "2019-07-15T09:09:55.761Z",
          error_code: 400,
          error_message: "Invalid values for \"slug\": \"invalid0,invalid1\"",
          credit_count: 0
        }
      })

    mock(fn
      %{method: :get, url: ^url_with_invalid_slugs} ->
        %Tesla.Env{
          status: 400,
          body: json_error
        }

      %{method: :get, url: ^url_with_cleaned_slugs} ->
        %Tesla.Env{
          status: 200,
          body: File.read!(Path.join(__DIR__, "data/cryptocurrency_info.json"))
        }
    end)

    CryptocurrencyInfo.fetch_data(["bitcoin", "invalid0", "invalid1"])
  end
end
