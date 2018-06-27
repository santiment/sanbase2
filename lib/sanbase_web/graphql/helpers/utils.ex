defmodule SanbaseWeb.Graphql.Helpers.Utils do
  def calibrate_interval(module, measurement, from, to, interval, data_points_count \\ 1000)

  def calibrate_interval(module, measurement, from, to, "", data_points_count) do
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

  def calibrate_interval_with_ma_interval(
        module,
        measurement,
        from,
        to,
        interval,
        _ma_interval,
        data_points_count \\ 1000
      ) do
    {:ok, from, to, interval} =
      calibrate_interval(module, measurement, from, to, interval, data_points_count)

    {int_interval, _} = Integer.parse(interval)
    ma_interval = div(7 * 24 * 60 * 60, int_interval)

    {:ok, from, to, interval, ma_interval}
  end

  def error_details(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
  end

  @spec format_error(Ecto.Changeset.error()) :: String.t()
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
