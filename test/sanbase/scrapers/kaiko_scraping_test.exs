defmodule Sanbase.KaikoTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  setup do
    project =
      insert(:project, %{
        slug: "bitcoin",
        source_slug_mappings: [
          build(:source_slug_mapping, %{source: "kaiko", slug: "btc"})
        ]
      })

    [project: project]
  end

  test "fetching data" do
    resp =
      {:ok,
       %HTTPoison.Response{
         body: File.read!(Path.join(__DIR__, "data/kaiko_response.json")),
         status_code: 200
       }}

    Sanbase.Mock.prepare_mock2(&HTTPoison.get/3, resp)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Kaiko.run()

      prices =
        Sanbase.InMemoryKafka.Producer.get_state()
        |> Map.get("asset_prices")

      # There 13 non-null prices in the JSON response. There are 26 results
      # because it will reuse the same JSON response for two fetches - one
      # with USD quote_asset and one with BTC
      assert length(prices) == 26

      {key, value_json} = Enum.at(prices, 0)
      assert key == "kaiko_bitcoin_2021-01-28T15:02:00.000Z"

      assert Jason.decode!(value_json) == %{
               "marketcap_usd" => nil,
               "price_btc" => 0.04220187108187633,
               "price_usd" => nil,
               "slug" => "bitcoin",
               "source" => "kaiko",
               "timestamp" => 1_611_846_120,
               "volume_usd" => nil
             }

      {key20, value_json20} = Enum.at(prices, 20)
      assert key20 == "kaiko_bitcoin_2021-01-28T15:00:50.000Z"

      assert Jason.decode!(value_json20) == %{
               "marketcap_usd" => nil,
               "price_btc" => nil,
               "price_usd" => 0.04222828954379179,
               "slug" => "bitcoin",
               "source" => "kaiko",
               "timestamp" => 1_611_846_050,
               "volume_usd" => nil
             }
    end)
  end
end
