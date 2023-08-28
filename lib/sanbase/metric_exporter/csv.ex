defmodule Sanbase.MetricExporter.CSV do
  require Logger

  alias Sanbase.Metric
  alias Sanbase.MetricExporter.S3

  @send_hour ~T[17:00:00]
  @decimals 8
  @dictionaries_path Path.join(__DIR__, "dictionary_files/")
  @dictionaries_files Path.wildcard("#{@dictionaries_path}/*")

  @number_word_map %{
    1 => "one",
    2 => "two",
    3 => "three",
    4 => "four",
    5 => "five",
    6 => "six",
    7 => "seven",
    8 => "eight",
    9 => "nine",
    10 => "ten",
    11 => "eleven",
    12 => "twelve"
  }

  @buckets [
    "0_to_0.001",
    "0.001_to_0.01",
    "0.01_to_0.1",
    "0.1_to_1",
    "1_to_10",
    "10_to_100",
    "100_to_1k",
    "1k_to_10k",
    "10k_to_100k",
    "100k_to_1M",
    "1M_to_10M",
    "10M_to_inf"
  ]

  @buckets_map Enum.with_index(@buckets)
               |> Enum.into(%{}, fn {range, index} ->
                 {range, "range_" <> @number_word_map[index + 1]}
               end)
  @buckets_map_reverse @buckets_map |> Enum.into(%{}, fn {a, b} -> {b, a} end)
  def buckets_map, do: @buckets_map
  def buckets_map_reverse, do: @buckets_map_reverse

  @metrics_map %{
    supply_distribution_1d: %{
      metrics: [
        "percent_of_holders_distribution_0_to_0.001",
        "percent_of_holders_distribution_0.001_to_0.01",
        "percent_of_holders_distribution_0.01_to_0.1",
        "percent_of_holders_distribution_0.1_to_1",
        "percent_of_holders_distribution_1_to_10",
        "percent_of_holders_distribution_10_to_100",
        "percent_of_holders_distribution_100_to_1k",
        "percent_of_holders_distribution_1k_to_10k",
        "percent_of_holders_distribution_10k_to_100k",
        "percent_of_holders_distribution_100k_to_1M",
        "percent_of_holders_distribution_1M_to_10M",
        "percent_of_holders_distribution_10M_to_inf",
        "percent_of_holders_distribution_combined_balance_0_to_0.001",
        "percent_of_holders_distribution_combined_balance_0.001_to_0.01",
        "percent_of_holders_distribution_combined_balance_0.01_to_0.1",
        "percent_of_holders_distribution_combined_balance_0.1_to_1",
        "percent_of_holders_distribution_combined_balance_1_to_10",
        "percent_of_holders_distribution_combined_balance_10_to_100",
        "percent_of_holders_distribution_combined_balance_100_to_1k",
        "percent_of_holders_distribution_combined_balance_1k_to_10k",
        "percent_of_holders_distribution_combined_balance_10k_to_100k",
        "percent_of_holders_distribution_combined_balance_100k_to_1M",
        "percent_of_holders_distribution_combined_balance_1M_to_10M",
        "percent_of_holders_distribution_combined_balance_10M_to_inf"
      ],
      interval: "1d"
    },
    active_supply_distribution_1d: %{
      metrics: [
        "percent_of_active_holders_distribution_0_to_0.001",
        "percent_of_active_holders_distribution_0.001_to_0.01",
        "percent_of_active_holders_distribution_0.01_to_0.1",
        "percent_of_active_holders_distribution_0.1_to_1",
        "percent_of_active_holders_distribution_1_to_10",
        "percent_of_active_holders_distribution_10_to_100",
        "percent_of_active_holders_distribution_100_to_1k",
        "percent_of_active_holders_distribution_1k_to_10k",
        "percent_of_active_holders_distribution_10k_to_100k",
        "percent_of_active_holders_distribution_100k_to_1M",
        "percent_of_active_holders_distribution_1M_to_10M",
        "percent_of_active_holders_distribution_10M_to_inf",
        "percent_of_active_holders_distribution_combined_balance_0_to_0.001",
        "percent_of_active_holders_distribution_combined_balance_0.001_to_0.01",
        "percent_of_active_holders_distribution_combined_balance_0.01_to_0.1",
        "percent_of_active_holders_distribution_combined_balance_0.1_to_1",
        "percent_of_active_holders_distribution_combined_balance_1_to_10",
        "percent_of_active_holders_distribution_combined_balance_10_to_100",
        "percent_of_active_holders_distribution_combined_balance_100_to_1k",
        "percent_of_active_holders_distribution_combined_balance_1k_to_10k",
        "percent_of_active_holders_distribution_combined_balance_10k_to_100k",
        "percent_of_active_holders_distribution_combined_balance_100k_to_1M",
        "percent_of_active_holders_distribution_combined_balance_1M_to_10M",
        "percent_of_active_holders_distribution_combined_balance_10M_to_inf"
      ],
      interval: "1d"
    },
    network_activity_1d: %{
      metrics: [
        "circulation",
        "circulation_1d",
        "circulation_7d",
        "circulation_30d",
        "circulation_60d",
        "circulation_90d",
        "circulation_180d",
        "circulation_365d",
        "circulation_3y",
        "circulation_5y",
        "circulation_10y"
      ],
      interval: "1d"
    },
    network_activity_1h: %{
      metrics: ["transaction_volume", "active_addresses_24h"],
      interval: "1h"
    },
    exchange_metrics_1h: %{
      metrics: ["exchange_inflow", "exchange_outflow", "exchange_balance", "active_deposits_5m"],
      interval: "1h"
    },
    exchange_metrics_1d: %{
      metrics: ["percent_of_total_supply_on_exchanges"],
      interval: "1d"
    },
    long_term_holders_1h: %{metrics: ["age_consumed"], interval: "1h"},
    long_term_holders_1d: %{
      metrics: [
        "dormant_circulation_90d",
        "dormant_circulation_180d",
        "dormant_circulation_365d",
        "dormant_circulation_2y",
        "dormant_circulation_3y",
        "dormant_circulation_5y",
        "dormant_circulation_10y"
      ],
      interval: "1d"
    },
    network_value_1h: %{
      metrics: [
        "network_profit_loss",
        "mvrv_usd_intraday",
        "mvrv_usd_intraday_1d",
        "mvrv_usd_intraday_7d",
        "mvrv_usd_intraday_30d",
        "mvrv_usd_intraday_60d",
        "mvrv_usd_intraday_90d",
        "mvrv_usd_intraday_180d",
        "mvrv_usd_intraday_365d",
        "mvrv_usd_intraday_2y",
        "mvrv_usd_intraday_3y",
        "mvrv_usd_intraday_5y",
        "mvrv_usd_intraday_10y"
      ],
      interval: "1h"
    },
    social_1h: %{
      metrics: [
        "social_volume_total",
        "social_dominance_total",
        "sentiment_volume_consumed_total"
      ],
      interval: "1h"
    },
    development_activity_1d: %{metrics: ["dev_activity_1d"], interval: "1d"}
  }

  def slugs() do
    Sanbase.Project.List.projects_slugs(
      order_by_rank: true,
      has_pagination?: true,
      pagination: %{page: 1, page_size: 200}
    )
    |> Enum.reject(fn slug -> String.starts_with?(slug, "p-") end)
    |> Enum.take(100)
  end

  def metrics_map, do: @metrics_map

  def dictionaries_files, do: @dictionaries_files

  def metrics do
    @metrics_map |> Enum.map(fn {_, v} -> v.metrics end) |> List.flatten()
  end

  def export_history(from, to) do
    Sanbase.DateTimeUtils.generate_dates_inclusive(from, to)
    |> Enum.each(&export/1)
  end

  def export_dicts_history(from, to) do
    Sanbase.DateTimeUtils.generate_dates_inclusive(from, to)
    |> Enum.each(fn date -> upload_dictionaries_s3(date |> to_string) end)
  end

  def export do
    yesterday = Timex.shift(Timex.now(), days: -1) |> DateTime.to_date()
    export(yesterday)
  end

  def export(date) do
    Logger.info("Start metrics csv exporter #{date}")

    slugs = slugs()
    date_str = date |> to_string
    from = date |> DateTime.new!(~T[00:00:00])
    to = date |> DateTime.new!(~T[23:59:59])

    uploaded_files =
      export_data(slugs, date, from, to)
      |> upload_files_s3(date_str)

    Logger.info("""
      Finish metrics csv exporter #{date}.
      Uploaded files: #{inspect(uploaded_files)}
    """)
  end

  def export_data(slugs, date, from, to) do
    export_data =
      @metrics_map
      |> Enum.reduce(%{}, fn {filename, file_metrics}, export_acc ->
        header = ["identifier", "datetime"] ++ camelize(file_metrics.metrics)
        filename = "#{filename}" <> "_santiment_#{format_dt(date, @send_hour)}.csv.gz"

        fetched_data = fetch_data(slugs, file_metrics.metrics, from, to, file_metrics.interval)

        data =
          Enum.reduce(slugs, [], fn slug, acc ->
            acc ++ run(slug, file_metrics.metrics, fetched_data, from, to, file_metrics.interval)
          end)

        Map.put(export_acc, filename, [header] ++ data)
      end)

    {filename, tw_data} = tw_data(date, from, to)
    Map.put(export_data, filename, tw_data)
  end

  def upload_files_s3(file_data_map, date_str) do
    for {filename, data} <- file_data_map do
      iodata = NimbleCSV.RFC4180.dump_to_iodata(data)
      gzdata = :zlib.gzip(iodata)
      do_upload_s3(filename, gzdata, date_str)
    end
  end

  def upload_dictionaries_s3(scope) do
    for file <- @dictionaries_files do
      do_upload_s3(file, scope)
    end
  end

  def do_upload_s3(file, scope) do
    S3.store({file, scope})
  end

  def do_upload_s3(filename, data, scope) do
    S3.store({%{filename: filename, binary: data}, scope})
  end

  # helpers

  defp tw_data(date, from, to) do
    filename = "trending_words_1h_santiment_#{format_dt(date, @send_hour)}.csv.gz"
    header = ["datetime"] ++ rename_column(Enum.to_list(1..10))

    {:ok, data} = Sanbase.SocialData.TrendingWords.get_trending_words(from, to, "1h", 10, :all)

    data =
      data
      |> Enum.sort_by(fn {dt, _} -> dt end, {:asc, DateTime})
      |> Enum.map(fn {dt, words} -> [dt] ++ Enum.reverse(Enum.map(words, & &1.word)) end)

    {filename, [header] ++ data}
  end

  defp fetch_data(slugs, metrics, from, to, interval) do
    metrics
    |> Enum.into(%{}, fn metric ->
      {metric, fetch_timeseries(slugs, metric, from, to, interval)}
    end)
  end

  defp run(slug, metrics, data, from, to, interval) do
    for metric <- metrics do
      data = data[metric][slug]

      case data do
        nil -> generate_empty_data(from, to, interval)
        [] -> generate_empty_data(from, to, interval)
        data -> data
      end
    end
    |> merge_by_dt()
    |> Enum.sort_by(fn {dt, _} -> dt end, {:asc, DateTime})
    |> Enum.map(fn {dt, values} ->
      [slug, DateTime.to_iso8601(dt)] ++ values
    end)
  end

  @doc ~s"""
  Return timeseries  data in the format
  %{
    "bitcoin" => [
      %{datetime: ~U[2023-08-25 00:00:00Z], value: 26048.932927770074},
      %{datetime: ~U[2023-08-26 00:00:00Z], value: 26009.348515545655},
      %{datetime: ~U[2023-08-27 00:00:00Z], value: 26087.470742809328},
      %{datetime: ~U[2023-08-28 00:00:00Z], value: 26159.70917904751}
    ],
    "ethereum" => [
      %{datetime: ~U[2023-08-25 00:00:00Z], value: 1653.171919615368},
      %{datetime: ~U[2023-08-26 00:00:00Z], value: 1646.344935140887},
      %{datetime: ~U[2023-08-27 00:00:00Z], value: 1657.3042178366325},
      %{datetime: ~U[2023-08-28 00:00:00Z], value: 1657.174284083438}
    ]
  }
  """
  def fetch_timeseries(slugs, metric, from, to, interval) do
    data = get_timeseries_data_per_slug!(metric, slugs, from, to, interval)

    Enum.reduce(slugs, %{}, fn slug, acc ->
      slug_data = extract_slug_data(data, slug)

      Map.put(acc, slug, slug_data)
    end)
  end

  defp get_timeseries_data_per_slug!(metric, slugs, from, to, interval) do
    case Sanbase.Metric.timeseries_data_per_slug(metric, %{slug: slugs}, from, to, interval) do
      {:ok, data} ->
        data

      {:error, reason} ->
        msg =
          "Error metrics csv exporter fetching timeseries_data_per_slug for metric=#{metric},slug=#{inspect(slugs)},from=#{from},to=#{to},interval=#{interval}"

        raise("#{msg}.Reason=#{inspect(reason)}")
    end
  end

  defp extract_slug_data(data, slug) do
    data
    |> Enum.map(fn map ->
      value = Enum.find_value(map.data, fn map -> if map.slug == slug, do: map.value end)

      %{
        datetime: map.datetime,
        value: value || ""
      }
    end)
  end

  defp merge_by_dt(list) do
    list
    |> Enum.map(fn list2 ->
      list2
      |> Enum.reduce(%{}, fn %{datetime: dt, value: v}, acc ->
        v = format_value(v)
        Map.put(acc, dt, List.wrap(v))
      end)
    end)
    |> Enum.reduce(%{}, fn map, acc -> merge_by_dt_key(acc, map) end)
  end

  defp merge_by_dt_key(map1, map2) when map1 == %{}, do: map2
  defp merge_by_dt_key(map1, map2) when map2 == %{}, do: map1

  defp merge_by_dt_key(map1, map2) do
    map1
    |> Enum.reduce(%{}, fn {dt, v}, acc ->
      v2 = map2[dt]
      Map.put(acc, dt, [v, v2] |> List.flatten())
    end)
  end

  defp generate_empty_data(from, to, interval) do
    from = Timex.beginning_of_day(from)
    count = (Timex.diff(to, from, :seconds) / Sanbase.DateTimeUtils.str_to_sec(interval)) |> round

    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    0..(count - 1)
    |> Enum.map(fn offset -> Timex.shift(from, seconds: interval_sec * offset) end)
    |> Enum.map(fn dt -> %{datetime: dt, value: ""} end)
  end

  def format_dt(date, send_hour) do
    date
    |> DateTime.new!(send_hour)
    |> DateTime.to_iso8601()
    |> String.replace(~r/[-:]/, "")
    |> String.replace(~r/\.\d+/, "")
  end

  def format_value(value, decimals \\ @decimals) do
    if is_float(value) do
      :erlang.float_to_binary(value, decimals: decimals)
    else
      value
    end
  end

  def camelize(names) when is_list(names) do
    names |> Enum.map(&range_metric_to_alias/1) |> Enum.map(&camelize/1)
  end

  def camelize(name) do
    Inflex.camelize(name, :lower)
  end

  def rename_column(numbers) when is_list(numbers) do
    Enum.map(numbers, &rename_column/1)
  end

  def rename_column(number) do
    "top" <> String.capitalize(@number_word_map[number])
  end

  def range_metric_to_alias(metric) do
    case Enum.find(@buckets, fn range -> String.ends_with?(metric, range) end) do
      nil -> metric
      range when is_binary(range) -> String.replace_trailing(metric, range, @buckets_map[range])
    end
  end

  def alias_to_range_metric(metric) do
    case Enum.find(@buckets_map_reverse |> Map.keys(), fn range ->
           String.ends_with?(metric, range)
         end) do
      nil ->
        metric

      range when is_binary(range) ->
        String.replace_trailing(metric, range, @buckets_map_reverse[range])
    end
  end
end
