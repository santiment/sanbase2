defmodule Sanbase.MetricCSVExporter do
  alias Sanbase.Metric

  @date "2021-12-16"
  @history_in_days 1
  @decimals 8
  # top 100 fixed at 24/08/2021
  @slugs [
    "bitcoin",
    "ethereum",
    "cardano",
    "binance-coin",
    "tether",
    "ripple",
    "solana",
    "polkadot-new",
    "usd-coin",
    "p-usd-coin",
    "dogecoin",
    "luna",
    "uniswap",
    "p-uniswap",
    "binance-usd",
    "avalanche",
    "litecoin",
    "p-chainlink",
    "chainlink",
    "wrapped-bitcoin",
    "shiba-inu",
    "bitcoin-cash",
    "algorand",
    "p-matic-network",
    "matic-network",
    "stellar",
    "file-coin",
    "internet-computer",
    "cosmos",
    "vechain",
    "axie-infinity",
    "tron",
    "ethereum-classic",
    "ftx-token",
    "multi-collateral-dai",
    "theta",
    "tezos",
    "bitcoin-bep2",
    "fantom",
    "hedera-hashgraph",
    "hedera",
    "monero",
    "crypto-com-coin",
    "elrond-egld",
    "eos",
    "pancakeswap",
    "klaytn",
    "iota",
    "ecash",
    "p-aave",
    "aave",
    "near-protocol",
    "quant",
    "bitcoin-sv",
    "the-graph",
    "neo",
    "kusama",
    "waves",
    "terrausd",
    "unus-sed-leo",
    "bittorrent",
    "harmony",
    "maker",
    "blockstack",
    "arweave",
    "omisego",
    "amp",
    "dash",
    "helium",
    "chiliz",
    "celo",
    "decred",
    "thorchain",
    "compound",
    "holo",
    "nem",
    "theta-fuel",
    "zcash",
    "icon",
    "xinfin-network",
    "decentraland",
    "revain",
    "celsius",
    "dydx",
    "sushi",
    "enjin-coin",
    "qtum",
    "trueusd",
    "huobi-token",
    "yearn-finance",
    "bitcoin-gold",
    "flow",
    "curve",
    "mdex",
    "zilliqa",
    "mina",
    "synthetix-network-token",
    "ravencoin",
    "basic-attention-token",
    "ren"
  ]

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
    "Supply distribution - 1d": %{
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
    "Network activity - 1d": %{
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
    "Network activity - 1h": %{
      metrics: ["transaction_volume", "active_addresses_24h"],
      interval: "1h"
    },
    "Exchange Metrics - 1h": %{
      metrics: ["exchange_inflow", "exchange_outflow", "exchange_balance", "active_deposits_5m"],
      interval: "1h"
    },
    "Exchange Metrics - 1d": %{
      metrics: ["percent_of_total_supply_on_exchanges"],
      interval: "1d"
    },
    "Long-term holders - 1h": %{metrics: ["age_consumed"], interval: "1h"},
    "Long-term holders - 1d": %{
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
    "Network value - 1h": %{
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
    "Social - 1h": %{
      metrics: [
        "social_volume_total",
        "social_dominance_total",
        "sentiment_volume_consumed_total"
      ],
      interval: "1h"
    },
    "Development activity - 1d": %{metrics: ["dev_activity"], interval: "1d"}
  }

  def metrics do
    @metrics |> Enum.map(fn {k, v} -> v.metrics end) |> List.flatten()
  end

  # Export all metrics in @metrics_map and place in proper csv file
  def export() do
    now = Timex.now()
    from = Timex.shift(now, days: -1) |> Timex.beginning_of_day()
    to = Timex.shift(now, days: -1) |> Timex.end_of_day()

    @metrics_map
    |> Enum.each(fn {filename, file_metrics} ->
      header = ["slug", "datetime"] ++ camelize(file_metrics.metrics)
      filename = "#{filename}" <> "_#{format_dt(now)}.csv"
      write_to_file(filename, [header])

      @slugs
      |> Enum.chunk_every(2)
      |> Enum.each(fn slugs ->
        data =
          file_metrics
          |> Map.merge(%{slugs: slugs})
          |> run(from, to)

        write_to_file(filename, data)
      end)
    end)
  end

  # Export trending words
  def export_tw() do
    now = Timex.now()
    from = Timex.shift(now, days: -1) |> Timex.beginning_of_day()
    to = Timex.shift(now, days: -1) |> Timex.end_of_day()

    filename = "Trending words - 1h_#{format_dt(now)}.csv"
    write_to_file(filename, [["datetime"] ++ rename_column(Enum.to_list(1..10))])

    do_export_tw(filename, from, to)
  end

  # helpers

  defp do_export_tw(filename, from, to) do
    {:ok, data} = Sanbase.SocialData.TrendingWords.get_trending_words(from, to, "1h", 10)

    data =
      data
      |> Enum.sort_by(fn {dt, _} -> dt end, {:asc, DateTime})
      |> Enum.map(fn {dt, words} -> [dt] ++ Enum.reverse(Enum.map(words, & &1.word)) end)

    write_to_file(filename, data)
  end

  defp run(%{metrics: metrics, interval: interval} = args, from, to) do
    for slug <- args[:slugs] do
      lists =
        for metric <- metrics do
          {:ok, data} = Metric.timeseries_data(metric, %{slug: slug}, from, to, interval)
          data
        end

      if Enum.all?(lists, fn list -> list == [] end) do
        []
      else
        lists
        |> Enum.map(fn
          list when list != [] -> list
          _ -> generate_empty_data(from, to, interval)
        end)
        |> merge_by_dt()
        |> Enum.sort_by(fn {dt, _} -> dt end, {:asc, DateTime})
        |> Enum.map(fn {dt, values} ->
          [slug, DateTime.to_iso8601(dt)] ++ values
        end)
      end
    end
    |> Enum.reject(fn list -> list == [] end)
    |> Enum.reduce([], fn list, acc -> acc ++ list end)
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

  defp write_to_file(filename, data) do
    filename = Path.join([@date, filename])
    {:ok, file} = File.open(filename, [:append])
    iodata = NimbleCSV.RFC4180.dump_to_iodata(data)
    File.write!(filename, iodata, [:append])
    File.close(file)
  end

  def format_dt(dt) do
    dt
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
