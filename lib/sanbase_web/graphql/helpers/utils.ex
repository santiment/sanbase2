defmodule SanbaseWeb.Graphql.Helpers.Utils do
  alias Sanbase.DateTimeUtils

  import Ecto.Query

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

  def ticker_by_slug("TOTAL_MARKET"), do: "TOTAL_MARKET"

  def ticker_by_slug(slug) do
    from(
      p in Sanbase.Model.Project,
      where: p.coinmarketcap_id == ^slug and not is_nil(p.ticker),
      select: p.ticker
    )
    |> Sanbase.Repo.one()
  end

  @doc ~s"""
  Works when the result is a list of elements that contain a datetime and the query arguments
  have a `from` argument. In that case the first element's `datetime` is update to be
  the max of `datetime` and `from` from the query.
  This is used when a query to influxdb is made. Influxdb can return a timestamp
  that's outside `from` - `to` interval due to its inner working with buckets
  """
  def fit_from_datetime([%{datetime: datetime} = first | rest], %{from: from_query_argument}) do
    [
      %{first | datetime: Enum.max_by([datetime, from_query_argument], &DateTime.to_unix/1)}
      | rest
    ]
  end

  def fit_from_datetime(enum, _args), do: enum

  # Private functions

  @spec format_error(Ecto.Changeset.error()) :: String.t()
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
