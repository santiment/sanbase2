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

      # There 13 non-null prices in the JSON response. There are 13 USD results
      # and 13 BTC results that get combined into one data point
      assert length(prices) == 13

      {key, value_json} = Enum.at(prices, 0)
      assert key == "kaiko_bitcoin_2021-01-28T15:00:00Z"

      assert Jason.decode!(value_json) == %{
               "marketcap_usd" => nil,
               "price_btc" => 0.04228463511481032,
               "price_usd" => 0.04228463511481032,
               "slug" => "bitcoin",
               "source" => "kaiko",
               "timestamp" => 1_611_846_000,
               "volume_usd" => nil
             }

      {key20, value_json20} = Enum.at(prices, 10)
      assert key20 == "kaiko_bitcoin_2021-01-28T15:01:40Z"

      assert Jason.decode!(value_json20) == %{
               "marketcap_usd" => nil,
               "price_btc" => 0.04222825282476801,
               "price_usd" => 0.04222825282476801,
               "slug" => "bitcoin",
               "source" => "kaiko",
               "timestamp" => 1_611_846_100,
               "volume_usd" => nil
             }
    end)
  end
end
