defmodule SanbaseWeb.Graphql.Helpers.Utils do
  def calibrate_interval(
        module,
        measurement,
        from,
        to,
        interval,
        min_interval,
        data_points_count \\ 500
      )

  def calibrate_interval(module, measurement, from, to, "", min_interval, data_points_count) do
    {:ok, first_datetime} = module.first_datetime(measurement)
    first_datetime = first_datetime || from

    from =
      max(
        DateTime.to_unix(from, :second),
        DateTime.to_unix(first_datetime, :second)
      )

    interval = max(div(DateTime.to_unix(to, :second) - from, data_points_count), min_interval)

    {:ok, DateTime.from_unix!(from), to, "#{interval}s"}
  end

  def calibrate_interval(
        _module,
        _measurement,
        from,
        to,
        interval,
        _min_interval,
        _data_points_count
      ) do
    {:ok, from, to, interval}
  end

  def calibrate_interval_with_ma_interval(
        module,
        measurement,
        from,
        to,
        interval,
        min_interval,
        ma_base,
        data_points_count \\ 1000
      ) do
    {:ok, from, to, interval} =
      calibrate_interval(module, measurement, from, to, interval, min_interval, data_points_count)

    ma_interval =
      max(div(compound_duration_to_seconds(ma_base), compound_duration_to_seconds(interval)), 2)

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

  defp compound_duration_to_seconds(interval) do
    {int_interval, duration_index} = Integer.parse(interval)

    case duration_index do
      "ns" -> div(int_interval, :math.pow(10, 9))
      "s" -> int_interval
      "m" -> int_interval * 60
      "h" -> int_interval * 60 * 60
      "d" -> int_interval * 24 * 60 * 60
      "w" -> int_interval * 7 * 24 * 60 * 60
      _ -> int_interval
    end
  end
end
