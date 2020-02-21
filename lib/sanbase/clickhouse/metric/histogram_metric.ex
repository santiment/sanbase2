defmodule Sanbase.Clickhouse.Metric.HistogramMetric do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Clickhouse.Metric.HistogramSqlQuery

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def histogram_data("age_distribution" = metric, slug, from, to, interval, limit) do
    {query, args} = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query, args, fn [unix, value] ->
      range_from = unix |> DateTime.from_unix!()

      range_to =
        [range_from |> Timex.shift(seconds: str_to_sec(interval)), to]
        |> Enum.min_by(&DateTime.to_unix/1)

      %{
        range: [range_from, range_to],
        value: value
      }
    end)
  end

  def histogram_data("price_histogram" = metric, slug, from, to, interval, limit) do
    {query, args} = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query, args, fn [price, amount] ->
      %{
        price: Sanbase.Math.to_float(price),
        value: Sanbase.Math.to_float(amount)
      }
    end)
    |> maybe_transform_into_buckets(limit)
  end

  # Aggregate the separate prices into `limit` number of evenly spaced buckets
  defp maybe_transform_into_buckets({:ok, data}, limit) do
    {min, max} = Enum.map(data, & &1.price) |> Sanbase.Math.min_max()

    # Avoid precision issues when using `round` for prices.
    min = Float.floor(min, 2)
    max = Float.ceil(max, 2)
    bucket_size = Float.round((max - min) / limit, 2)

    # Generate ranges tuples in the format needed by Stream.unfold/2
    price_ranges = fn x ->
      [lower, upper] = [Float.round(x, 2), Float.round(x + bucket_size, 2)]
      {[lower, upper], upper}
    end

    # Generate limit number of ranges to properly empty ranges as 0
    ranges_map =
      Stream.unfold(min, price_ranges)
      |> Enum.take(limit)
      |> Enum.into(%{}, fn range -> {range, 0.0} end)

    # Map every price to the proper range
    price_to_range = fn price ->
      bucket = floor((price - min) / bucket_size)
      lower = min + bucket * bucket_size
      upper = min + (1 + bucket) * bucket_size

      [Float.round(lower, 2), Float.round(upper, 2)]
    end

    # Put every amount moved at a given price in the proper bucket
    data =
      Enum.reduce(data, ranges_map, fn %{price: price, value: value}, acc ->
        key = price_to_range.(price)
        Map.update(acc, key, 0.0, fn curr_amount -> Float.round(curr_amount + value, 2) end)
      end)
      |> Enum.map(fn {range, amount} -> %{range: range, value: amount} end)
      |> Enum.sort_by(fn %{range: [range_start | _]} -> range_start end)

    {:ok, data}
  end

  defp maybe_transform_into_buckets({:error, error}, _), do: {:error, error}
end
