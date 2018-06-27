defmodule SanbaseWeb.Graphql.Helpers.Utils do
  def calibrate_interval(module, measurement, from, to, "", data_points_count \\ 1000) do
    {:ok, first_datetime} = module.first_datetime(measurement)

    from =
      max(
        DateTime.to_unix(from, :second),
        DateTime.to_unix(first_datetime, :second)
      )

    interval = div(DateTime.to_unix(to, :second) - from, data_points_count)

    {:ok, DateTime.from_unix!(from), to, "#{interval}s"}
  end

  def calibrate_interval(_module, _measurement, from, to, interval, _data_points_count) do
    {:ok, from, to, interval}
  end
end
