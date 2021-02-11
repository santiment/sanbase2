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
    resp1 =
      {:ok,
       %HTTPoison.Response{
         body: File.read!(Path.join(__DIR__, "data/kaiko_response_1.json")),
         status_code: 200
       }}

    resp2 =
      {:ok,
       %HTTPoison.Response{
         body: File.read!(Path.join(__DIR__, "data/kaiko_response_2.json")),
         status_code: 200
       }}

    mock_fun =
      [
        fn -> resp1 end,
        fn -> resp2 end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 3)

    Sanbase.Mock.prepare_mock(HTTPoison, :get, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Kaiko.run(rounds_per_minute: 1)

      prices =
        Sanbase.InMemoryKafka.Producer.get_state()
        |> Map.get("asset_prices")

      # There 15 non-null prices in the JSON response. There are 13 USD results
      # that have matching 13 BTC results (same datetime) that get combined into
      # one data point.
      # There is also 1 USD price without matching BTC price and vice versa
      assert length(prices) == 15

      {key, value_json} = Enum.at(prices, 0)
      assert key == "kaiko_bitcoin_2021-01-28T14:57:40Z"

      assert Jason.decode!(value_json) == %{
               "marketcap_usd" => nil,
               "price_btc" => nil,
               "price_usd" => 15.25,
               "slug" => "bitcoin",
               "source" => "kaiko",
               "timestamp" => 1_611_845_860,
               "volume_usd" => nil
             }

      {key14, value_json14} = Enum.at(prices, 14)
      assert key14 == "kaiko_bitcoin_2021-01-28T15:02:00Z"

      assert Jason.decode!(value_json14) == %{
               "marketcap_usd" => nil,
               "price_btc" => 0.04220187108187633,
               "price_usd" => 11.98,
               "slug" => "bitcoin",
               "source" => "kaiko",
               "timestamp" => 1_611_846_120,
               "volume_usd" => nil
             }
    end)
  end
end
