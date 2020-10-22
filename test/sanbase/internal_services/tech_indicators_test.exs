defmodule Sanbase.TechIndicatorsTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import Sanbase.Factory

  alias Sanbase.TechIndicators

  setup do
    [
      project: insert(:random_erc20_project)
    ]
  end

  test "fetch price_volume_diff", context do
    response =
      {:ok,
       %HTTPoison.Response{
         body: """
         [
           #{Sanbase.TechIndicatorsTestResponse.price_volume_diff_prepend_response()},
           {
             "price_volume_diff": 0,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516406400
           },
           {
             "price_volume_diff": -0.014954423076923185,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516492800
           },
           {
             "price_volume_diff": -0.02373337292856359,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516579200
           }
         ]
         """,
         status_code: 200
       }}

    Sanbase.Mock.prepare_mock2(&HTTPoison.get/3, response)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        TechIndicators.PriceVolumeDifference.price_volume_diff(
          context.project,
          "USD",
          DateTime.from_unix!(1_516_406_400),
          DateTime.from_unix!(1_516_579_200),
          "1d",
          "bohman",
          14,
          7
        )

      expected_result =
        {:ok,
         [
           %{
             price_volume_diff: 0.0,
             price_change: 0.04862261825993345,
             volume_change: 0.030695260272520467,
             datetime: DateTime.from_unix!(1_516_406_400)
           },
           %{
             price_volume_diff: -0.014954423076923185,
             price_change: 0.04862261825993345,
             volume_change: 0.030695260272520467,
             datetime: DateTime.from_unix!(1_516_492_800)
           },
           %{
             price_volume_diff: -0.02373337292856359,
             price_change: 0.04862261825993345,
             volume_change: 0.030695260272520467,
             datetime: DateTime.from_unix!(1_516_579_200)
           }
         ]}

      assert result == expected_result
    end)
  end

  test "fetch twitter mention count", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"mention_count\": 0, \"timestamp\": 1516406400}, {\"mention_count\": 1234, \"timestamp\": 1516492800}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.twitter_mention_count(
        context.project.ticker,
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_492_800),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  mention_count: 0,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  mention_count: 1234,
                  datetime: DateTime.from_unix!(1_516_492_800)
                }
              ]}
  end

  test "fetch emojis_sentiment", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"sentiment\": 0, \"timestamp\": 1516406400}, {\"sentiment\": 1234, \"timestamp\": 1516492800}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.emojis_sentiment(
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_492_800),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  sentiment: 0,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  sentiment: 1234,
                  datetime: DateTime.from_unix!(1_516_492_800)
                }
              ]}
  end
end
