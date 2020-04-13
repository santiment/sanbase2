defmodule Sanbase.Clickhouse.Metric.HistogramMetric do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Clickhouse.Metric.HistogramSqlQuery

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def histogram_data("age_distribution" = metric, %{slug: slug}, from, to, interval, limit) do
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

  def histogram_data(metric, %{slug: slug}, from, to, interval, limit)
      when metric in ["price_histogram", "spent_coins_cost", "all_spent_coins_cost"] do
    {query, args} = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query, args, fn [price, amount] ->
      %{
        price: Sanbase.Math.to_float(price),
        value: Sanbase.Math.to_float(amount)
      }
    end)
    |> maybe_transform_into_buckets(slug, from, to, limit)
  end

  def first_datetime(metric, %{slug: _} = selector)
      when metric in ["price_histogram", "spent_coins_cost", "all_spent_coins_cost"] do
    with {:ok, dt1} <- Sanbase.Metric.first_datetime("price_usd", selector),
         {:ok, dt2} <- Sanbase.Metric.first_datetime("age_distribution", selector) do
      {:ok, Enum.max_by([dt1, dt2], &DateTime.to_unix/1)}
    end
  end

  def last_datetime_computed_at(metric, %{slug: _} = selector)
      when metric in ["price_histogram", "spent_coins_cost", "all_spent_coins_cost"] do
    with {:ok, dt1} <- Sanbase.Metric.last_datetime_computed_at("price_usd", selector),
         {:ok, dt2} <- Sanbase.Metric.last_datetime_computed_at("age_distribution", selector) do
      {:ok, Enum.min_by([dt1, dt2], &DateTime.to_unix/1)}
    end
  end

  # Aggregate the separate prices into `limit` number of evenly spaced buckets
  defp maybe_transform_into_buckets({:ok, []}, _slug, _from, _to, _limit), do: {:ok, []}

  defp maybe_transform_into_buckets({:ok, data}, slug, from, to, limit) do
    {min, max} = Enum.map(data, & &1.price) |> Sanbase.Math.min_max()

    # Avoid precision issues when using `round` for prices.
    min = Float.floor(min, 2)
    max = Float.ceil(max, 2)
    # `limit - 1` because one of the buckets will be split into 2
    bucket_size = Enum.max([Float.round((max - min) / (limit - 1), 2), 0.01])

    # Generate the range for given low and high price
    low_high_range = fn low, high ->
      [Float.round(low, 2), Float.round(high, 2)]
    end

    # Generate ranges tuples in the format needed by Stream.unfold/2
    price_ranges = fn value ->
      [lower, upper] = low_high_range.(value, value + bucket_size)
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

      low_high_range.(lower, upper)
    end

    # Get the average price for the queried. time range. It will break the [X,Y]
    # price interval containing that price into [X, price_break] and [price_break, Y]
    {:ok, %{^slug => price_break}} =
      Sanbase.Metric.aggregated_timeseries_data("price_usd", %{slug: slug}, from, to, :avg)

    price_break = price_break |> Sanbase.Math.round_float()
    price_break_range = price_to_range.(price_break)

    # Put every amount moved at a given price in the proper bucket
    bucketed_data =
      Enum.reduce(data, ranges_map, fn %{price: price, value: value}, acc ->
        key = price_to_range.(price)
        Map.update(acc, key, 0.0, fn curr_amount -> Float.round(curr_amount + value, 2) end)
      end)
      |> break_bucket(data, price_break_range, price_break)
      |> Enum.map(fn {range, amount} -> %{range: range, value: amount} end)
      |> Enum.sort_by(fn %{range: [range_start | _]} -> range_start end)

    {:ok, bucketed_data}
  end

  defp maybe_transform_into_buckets({:error, error}, _slug, _from, _to, _limit),
    do: {:error, error}

  defp break_bucket(bucketed_data, original_data, [low, high], divider) do
    {lower_half_amount, upper_half_amount} =
      original_data
      |> Enum.reduce({0.0, 0.0}, fn %{price: price, value: value}, {acc_lower, acc_upper} ->
        cond do
          price >= low and price < divider -> {acc_lower + value, acc_upper}
          price >= divider and price < high -> {acc_lower, acc_upper + value}
          true -> {acc_lower, acc_upper}
        end
      end)

    bucketed_data
    |> Map.delete([low, high])
    |> Map.put([low, divider], Float.round(lower_half_amount, 2))
    |> Map.put([divider, high], Float.round(upper_half_amount, 2))
  end
end
