defmodule SanbaseWeb.Graphql.Helpers.CalibrateInterval do
  alias Sanbase.DateTimeUtils

  def calibrate(module, id, from, to, interval, min_seconds \\ 300, max_data_points \\ 500)

  def calibrate(module, id, from, to, "", min_seconds, max_data_points) do
    with {:ok, first_datetime} <- module.first_datetime(id) do
      first_datetime = first_datetime || from

      from =
        max(
          DateTime.to_unix(from, :second),
          DateTime.to_unix(first_datetime, :second)
        )

      interval =
        max(
          div(DateTime.to_unix(to, :second) - from, max_data_points),
          min_seconds
        )

      {:ok, DateTime.from_unix!(from), to, "#{interval}s"}
    end
  end

  def calibrate(_module, _id, from, to, interval, _min_interval, _max_data_points) do
    {:ok, from, to, interval}
  end

  def calibrate(module, metric, slug, from, to, "", min_seconds, max_data_points) do
    {:ok, first_datetime} = module.first_datetime(metric, slug)

    first_datetime = first_datetime || from

    from =
      max(
        DateTime.to_unix(from, :second),
        DateTime.to_unix(first_datetime, :second)
      )

    interval =
      max(
        div(DateTime.to_unix(to, :second) - from, max_data_points),
        min_seconds
      )

    {:ok, DateTime.from_unix!(from), to, "#{interval}s"}
  end

  def calibrate(
        _module,
        _metric,
        _id,
        from,
        to,
        interval,
        _min_interval,
        _max_data_points
      ) do
    {:ok, from, to, interval}
  end

  def calibrate_moving_average(
        module,
        id,
        from,
        to,
        interval,
        min_interval,
        moving_average_base,
        max_data_points \\ 500
      ) do
    {:ok, from, to, interval} =
      calibrate(module, id, from, to, interval, min_interval, max_data_points)

    ma_interval =
      max(
        div(
          DateTimeUtils.str_to_sec(moving_average_base),
          DateTimeUtils.str_to_sec(interval)
        ),
        2
      )

    {:ok, from, to, interval, ma_interval}
  end

  def calibrate_incomplete_data_params(true, _module, _metric, from, to) do
    {:ok, from, to}
  end

  def calibrate_incomplete_data_params(false, module, metric, from, to) do
    case module.has_incomplete_data?(metric) do
      true -> rewrite_params_incomplete_data(from, to)
      false -> {:ok, from, to}
    end
  end

  defp rewrite_params_incomplete_data(from, to) do
    end_of_previous_day = Timex.now() |> Timex.beginning_of_day() |> Timex.shift(microseconds: -1)

    case DateTime.compare(from, end_of_previous_day) != :lt do
      true ->
        {:error,
         """
         The time range provided [#{from} - #{to}] is contained in today. The metric
         requested could have incomplete data as it's calculated since the beginning
         of the day and not for the last 24 hours. If you still want to see this
         data you can pass the flag `includeIncompleteData: true` in the
         `timeseriesData` arguments
         """}

      false ->
        to =
          if DateTime.compare(to, end_of_previous_day) == :gt, do: end_of_previous_day, else: to

        {:ok, from, to}
    end
  end
end
