defmodule Sanbase.TechIndicatorsTestResponse do
  @doc ~s"""
  The price volume difference function modifies the `from` datetimes because
  otherwise the first N values will be null because of the moving average calculations.
  When mocking in tests this should be taken into account. To change the tests
  just prepend the result returned in the mock with the output of this function.
  These values will be cut off of the returned result of the function
  """
  def price_volume_diff_prepend_response(times \\ 21) do
    ~s/
      {
        "price_volume_diff": 0,
        "price_change": 0.04862261825993345,
        "volume_change": 0.030695260272520467,
        "timestamp": 1516406400
      }
    /
    |> List.wrap()
    |> Stream.cycle()
    |> Enum.take(times)
    |> Enum.join(", ")
  end
end
