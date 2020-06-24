defmodule Sanbase.Clickhouse.Exchanges.MarketDepth do
  use Ecto.Schema

  @exchanges ["Binance", "Bitfinex", "Kraken", "Poloniex", "Bitrex"]

  alias Sanbase.ClickhouseRepo

  @table "exchange_market_depth"
  schema @table do
    field(:timestamp, :utc_datetime)
    field(:source, :string)
    field(:symbol, :string)
    field(:ask, :float)
    field(:asks_0_25_percent_depth, :float)
    field(:asks_0_25_percent_volume, :float)
    field(:asks_0_5_percent_depth, :float)
    field(:asks_0_5_percent_volume, :float)
    field(:asks_0_75_percent_depth, :float)
    field(:asks_0_75_percent_volume, :float)
    field(:asks_10_percent_depth, :float)
    field(:asks_10_percent_volume, :float)
    field(:asks_1_percent_depth, :float)
    field(:asks_1_percent_volume, :float)
    field(:asks_20_percent_depth, :float)
    field(:asks_20_percent_volume, :float)
    field(:asks_2_percent_depth, :float)
    field(:asks_2_percent_volume, :float)
    field(:asks_30_percent_depth, :float)
    field(:asks_30_percent_volume, :float)
    field(:asks_5_percent_depth, :float)
    field(:asks_5_percent_volume, :float)
    field(:bid, :float)
    field(:bids_0_25_percent_depth, :float)
    field(:bids_0_25_percent_volume, :float)
    field(:bids_0_5_percent_depth, :float)
    field(:bids_0_5_percent_volume, :float)
    field(:bids_0_75_percent_depth, :float)
    field(:bids_0_75_percent_volume, :float)
    field(:bids_10_percent_depth, :float)
    field(:bids_10_percent_volume, :float)
    field(:bids_1_percent_depth, :float)
    field(:bids_1_percent_volume, :float)
    field(:bids_20_percent_depth, :float)
    field(:bids_20_percent_volume, :float)
    field(:bids_2_percent_depth, :float)
    field(:bids_2_percent_volume, :float)
    field(:bids_30_percent_depth, :float)
    field(:bids_30_percent_volume, :float)
    field(:bids_5_percent_depth, :float)
    field(:bids_5_percent_volume, :float)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change exchange trades")

  def last_exchange_market_depth(exchange, ticker_pair, limit) when exchange in @exchanges do
    {query, args} = last_exchange_market_depth_query(exchange, ticker_pair, limit)

    ClickhouseRepo.query_transform(query, args, fn
      [
        timestamp,
        source,
        symbol,
        ask,
        asks025_percent_depth,
        asks025_percent_volume,
        asks05_percent_depth,
        asks05_percent_volume,
        asks075_percent_depth,
        asks075_percent_volume,
        asks10_percent_depth,
        asks10_percent_volume,
        asks1_percent_depth,
        asks1_percent_volume,
        asks20_percent_depth,
        asks20_percent_volume,
        asks2_percent_depth,
        asks2_percent_volume,
        asks30_percent_depth,
        asks30_percent_volume,
        asks5_percent_depth,
        asks5_percent_volume,
        bid,
        bids025_percent_depth,
        bids025_percent_volume,
        bids05_percent_depth,
        bids05_percent_volume,
        bids075_percent_depth,
        bids075_percent_volume,
        bids10_percent_depth,
        bids10_percent_volume,
        bids1_percent_depth,
        bids1_percent_volume,
        bids20_percent_depth,
        bids20_percent_volume,
        bids2_percent_depth,
        bids2_percent_volume,
        bids30_percent_depth,
        bids30_percent_volume,
        bids5_percent_depth,
        bids5_percent_volume
      ] ->
        %{
          datetime: timestamp |> DateTime.from_unix!(),
          exchange: source,
          ticker_pair: symbol,
          ask: ask,
          asks025_percent_depth: asks025_percent_depth,
          asks025_percent_volume: asks025_percent_volume,
          asks05_percent_depth: asks05_percent_depth,
          asks05_percent_volume: asks05_percent_volume,
          asks075_percent_depth: asks075_percent_depth,
          asks075_percent_volume: asks075_percent_volume,
          asks10_percent_depth: asks10_percent_depth,
          asks10_percent_volume: asks10_percent_volume,
          asks1_percent_depth: asks1_percent_depth,
          asks1_percent_volume: asks1_percent_volume,
          asks20_percent_depth: asks20_percent_depth,
          asks20_percent_volume: asks20_percent_volume,
          asks2_percent_depth: asks2_percent_depth,
          asks2_percent_volume: asks2_percent_volume,
          asks30_percent_depth: asks30_percent_depth,
          asks30_percent_volume: asks30_percent_volume,
          asks5_percent_depth: asks5_percent_depth,
          asks5_percent_volume: asks5_percent_volume,
          bid: bid,
          bids025_percent_depth: bids025_percent_depth,
          bids025_percent_volume: bids025_percent_volume,
          bids05_percent_depth: bids05_percent_depth,
          bids05_percent_volume: bids05_percent_volume,
          bids075_percent_depth: bids075_percent_depth,
          bids075_percent_volume: bids075_percent_volume,
          bids10_percent_depth: bids10_percent_depth,
          bids10_percent_volume: bids10_percent_volume,
          bids1_percent_depth: bids1_percent_depth,
          bids1_percent_volume: bids1_percent_volume,
          bids20_percent_depth: bids20_percent_depth,
          bids20_percent_volume: bids20_percent_volume,
          bids2_percent_depth: bids2_percent_depth,
          bids2_percent_volume: bids2_percent_volume,
          bids30_percent_depth: bids30_percent_depth,
          bids30_percent_volume: bids30_percent_volume,
          bids5_percent_depth: bids5_percent_depth,
          bids5_percent_volume: bids5_percent_volume
        }
    end)
  end

  defp last_exchange_market_depth_query(exchange, ticker_pair, limit) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      source,
      symbol,
      ask,
      asks_0_25_percent_depth,
      asks_0_25_percent_volume,
      asks_0_5_percent_depth,
      asks_0_5_percent_volume,
      asks_0_75_percent_depth,
      asks_0_75_percent_volume,
      asks_10_percent_depth,
      asks_10_percent_volume,
      asks_1_percent_depth,
      asks_1_percent_volume,
      asks_20_percent_depth,
      asks_20_percent_volume,
      asks_2_percent_depth,
      asks_2_percent_volume,
      asks_30_percent_depth,
      asks_30_percent_volume,
      asks_5_percent_depth,
      asks_5_percent_volume,
      bid,
      bids_0_25_percent_depth,
      bids_0_25_percent_volume,
      bids_0_5_percent_depth,
      bids_0_5_percent_volume,
      bids_0_75_percent_depth,
      bids_0_75_percent_volume,
      bids_10_percent_depth,
      bids_10_percent_volume,
      bids_1_percent_depth,
      bids_1_percent_volume,
      bids_20_percent_depth,
      bids_20_percent_volume,
      bids_2_percent_depth,
      bids_2_percent_volume,
      bids_30_percent_depth,
      bids_30_percent_volume,
      bids_5_percent_depth,
      bids_5_percent_volume
    FROM #{@table}
    PREWHERE
      source = ?1 AND symbol = ?2
    ORDER BY dt DESC
    LIMIT ?3
    """

    args = [
      exchange,
      ticker_pair,
      limit
    ]

    {query, args}
  end
end
