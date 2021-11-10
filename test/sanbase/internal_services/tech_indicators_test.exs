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
    mock(
      HTTPoison,
      :get,
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
           },
           {
             "price_volume_diff": -0.030529013702074614,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516665600
           },
           {
             "price_volume_diff": -0.0239400614928722,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516752000
           }
         ]
         """,
         status_code: 200
       }}
    )

    result =
      TechIndicators.PriceVolumeDifference.price_volume_diff(
        context.project,
        "USD",
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_752_000),
        "1d",
        "bohman",
        14,
        7
      )

    assert result ==
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
                },
                %{
                  price_volume_diff: -0.030529013702074614,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  price_volume_diff: -0.0239400614928722,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_752_000)
                }
              ]}
  end
end
