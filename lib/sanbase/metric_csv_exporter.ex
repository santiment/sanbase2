defmodule Sanbase.MetricCSVExporter do
  alias Sanbase.Metric

  # top 100 fixed at 24/08/2021
  @slugs [
    "bitcoin",
    "ethereum",
    "cardano",
    "binance-coin",
    "tether",
    "ripple",
    "dogecoin",
    "polkadot-new",
    "usd-coin",
    "solana",
    "uniswap",
    "bitcoin-cash",
    "chainlink",
    "litecoin",
    "binance-usd",
    "luna",
    "matic-network",
    "internet-computer",
    "wrapped-bitcoin",
    "stellar",
    "ethereum-classic",
    "vechain",
    "avalanche",
    "file-coin",
    "theta",
    "tron",
    "multi-collateral-dai",
    "monero",
    "pancakeswap",
    "eos",
    "aave",
    "cosmos",
    "ftx-token",
    "the-graph",
    "axie-infinity",
    "klaytn",
    "neo",
    "crypto-com-coin",
    "maker",
    "bitcoin-bep2",
    "algorand",
    "tezos",
    "iota",
    "shiba-inu",
    "bitcoin-sv",
    "amp",
    "bittorrent",
    "elrond-egld",
    "unus-sed-leo",
    "dash",
    "kusama",
    "waves",
    "thorchain",
    "compound",
    "huobi-token",
    "near-protocol",
    "hedera-hashgraph",
    "helium",
    "decred",
    "chiliz",
    "terrausd",
    "quant",
    "xinfin-network",
    "zcash",
    "holo",
    "nem",
    "theta-fuel",
    "blockstack",
    "sushi",
    "decentraland",
    "enjin-coin",
    "synthetix-network-token",
    "telcoin",
    "yearn-finance",
    "fantom",
    "ravencoin",
    "qtum",
    "celsius",
    "zilliqa",
    "flow",
    "trueusd",
    "basic-attention-token",
    "okb",
    "bitcoin-gold",
    "harmony",
    "audius",
    "kucoin-shares",
    "nexo",
    "digibyte",
    "swissborg",
    "bancor",
    "ontology",
    "icon",
    "siacoin",
    "arweave",
    "0x",
    "omisego",
    "curve",
    "paxos-standard",
    "nano"
  ]

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
        "daily_active_addresses",
        "network_growth",
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
    "Network activity - 1h": %{metrics: ["transaction_volume"], interval: "1h"},
    "Exchange Metrics - 1h": %{
      metrics: ["exchange_inflow", "exchange_outflow", "exchange_balance"],
      interval: "1h"
    },
    "Exchange Metrics - 1d": %{
      metrics: ["active_deposits", "percent_of_total_supply_on_exchanges"],
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

  # Export all metrics in @metrics_map and place in proper csv file
  def export() do
    to = Timex.now()
    from = Timex.shift(to, days: -(365 * 2))

    @metrics_map
    |> Enum.each(fn {filename, file_metrics} ->
      header = ["slug", "datetime"] ++ file_metrics.metrics
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
    filename = "Trending words - 1h"
    write_to_file(filename, [["datetime"] ++ Enum.to_list(1..10)])

    now = Timex.now()

    from = Timex.shift(now, days: -(365 * 2))
    to = Timex.shift(now, days: -365)
    do_export_tw(filename, from, to)

    from = Timex.shift(now, days: -364)
    to = now
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

  defp write_to_file(key, data) do
    filename = "#{key}.csv"
    {:ok, file} = File.open(filename, [:append])
    iodata = NimbleCSV.RFC4180.dump_to_iodata(data)
    File.write!("#{key}.csv", iodata, [:append])
    File.close(file)
  end
end
