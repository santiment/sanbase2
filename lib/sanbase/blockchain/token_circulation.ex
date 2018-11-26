defmodule Sanbase.Blockchain.TokenCirculation do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Timescaledb

  @table Timescaledb.table_name("eth_coin_circulation")
  @interval_mapping %{
    less_than_a_day: "_-1d",
    between_a_day_and_a_week: "1d-1w",
    between_a_week_and_a_month: "1w-1m",
    between_a_month_and_three_weeks: "1m-3m",
    between_three_months_and_six_months: "3m-6m",
    between_six_months_and_a_year: "6m-12m",
    between_a_year_and_eighteen_months: "12m-18m",
    between_eighteen_months_and_two_years: "18m-24m",
    between_two_years_and_three_years: "2y-3y",
    between_three_years_and_five_years: "3y-5y",
    more_than_five_years: "5y-_"
  }

  def token_circulation(tc_interval, contract, from, to, interval, token_decimals \\ 0) do
    interval_in_secs = Timescaledb.transform_interval(interval).secs

    case rem(interval_in_secs, 86400) do
      0 -> calculate_token_circulation(tc_interval, contract, from, to, interval, token_decimals)
      _ -> {:error, "The interval must consist of whole days"}
    end
  end

  defp calculate_token_circulation(tc_interval, contract, from, to, interval, token_decimals) do
    args = [from, to, contract]

    """
    SELECT sum("#{@interval_mapping[tc_interval]}") AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> Timescaledb.bucket_by_interval(args, interval)
    |> Timescaledb.timescaledb_execute(fn [datetime, token_circulation] ->
      %{
        datetime: Timescaledb.timestamp_to_datetime(datetime),
        token_circulation: token_circulation / :math.pow(10, token_decimals)
      }
    end)
  end

  def token_circulation!(tc_interval, contract, from, to, interval, token_decimals \\ 0) do
    case token_circulation(tc_interval, contract, from, to, interval, token_decimals) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def first_datetime(contract) do
    "FROM #{@table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end
end
