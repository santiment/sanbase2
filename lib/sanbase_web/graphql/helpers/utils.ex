defmodule SanbaseWeb.Graphql.Helpers.Utils do
  alias Sanbase.DateTimeUtils

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
        data_points_count \\ 500
      ) do
    {:ok, from, to, interval} =
      calibrate_interval(module, measurement, from, to, interval, min_interval, data_points_count)

    ma_interval =
      max(
        div(
          DateTimeUtils.compound_duration_to_seconds(ma_base),
          DateTimeUtils.compound_duration_to_seconds(interval)
        ),
        2
      )

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
