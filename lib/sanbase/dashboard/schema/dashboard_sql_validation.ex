defmodule Sanbase.Dashboard.SqlValidation do
  @validation_functions [:from_clauses]

  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(query) do
    query =
      String.replace(query, ["\r\n", "\n"], " ")
      |> String.replace(~r|\s+|, " ")
      |> String.trim()
      |> String.downcase()

    Enum.reduce_while(@validation_functions, :ok, fn fun, _acc ->
      case validate(fun, query) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @allowed_tables ~w(
    asset_metadata metric_metadata asset_prices_v3 asset_price_pairs_only intraday_metrics
    daily_metrics_v2 numbers balances_aggregated xrp_balances doge_balances eth_balancs
    btc_balances cardano_balances bnb_balances bch_balances trending_words_v4_top_500 signals
    signals_metadata polygon_transfers eth_transfers erc20_transfers erc20_transfers_dt_order
    github_v2 daily_label_based_metrics
  )

  def validate(:from_clauses, query) do
    Regex.scan(~r/from\s+([\w,.]+)/, query, include_captures: true, trim: true)
    |> Enum.reduce_while(:ok, fn
      [_, "system." <> _], _acc ->
        {:halt, {:error, "system tables are not allowed"}}

      [_, table], _acc ->
        case table in @allowed_tables do
          true -> {:cont, :ok}
          false -> {:halt, {:error, "table #{table} is not allowed"}}
        end
    end)
  end
end
