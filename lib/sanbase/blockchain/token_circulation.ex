defmodule Sanbase.Blockchain.TokenCirculation do
  @moduledoc ~s"""
  Token circulation shows the distribution of non-transacted tokens over time.
  In other words - how many tokens are being HODLed, and for how long.

  Practical example:
  In one particular day Alice sends 20 ETH to Bob, Bob sends 10 ETH to Charlie
  and Charlie sends 5 ETH to Dean. This corresponds to the amount of tokens that have
  been HODLed for less than 1 day ("_-1d" column in the table)
  ###
     Alice  -- 20 ETH -->  Bob
                            |
                          10 ETH
                            |
                            v
     Dean <-- 5  ETH -- Charlie
  ###

  In this scenario the transaction volume is 20 + 10 + 5 = 35 ETH, though the ETH
  in circulation is 20 ETH.

  This can be explained as having twenty $1 bills. Alice sends all of them to Bob,
  Bob sends 10 of the received bills to Charlie and Charlie sends 5 of them to Dean.

  One of the most useful properities of Token Circulation is that this metric is immune
  to mixers and gives a much better view of the actual amount of tokens that are being
  transacted
  """

  @type t :: %__MODULE__{
          timestamp: %DateTime{},
          contract_address: String.t(),
          less_than_a_day: float()
        }

  @typedoc ~s"""
  Returned by the `token_circulation/6` and `token_circulation!/6` functions.
  """
  @type circulation_map :: %{
          datetime: %DateTime{},
          token_circulation: float()
        }
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

  @primary_key false
  schema @table do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:less_than_a_day, :float, source: :"_-1d")
  end

  def changeset(%__MODULE__{} = token_circulation, attrs \\ %{}) do
    token_circulation
    |> cast(attrs, [:timestamp, :contract_address, :less_than_a_day])
    |> validate_number(:less_than_a_day, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  @doc ~s"""
  Return the token circulation for a given contract and time restrictions.
  Currently supports only the token circulation for less than a day.
  """
  @spec token_circulation(
          :less_than_a_day,
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: {:ok, list(circulation_map)} | {:error, String.t()}
  def token_circulation(:less_than_a_day, contract, from, to, interval, token_decimals \\ 0) do
    interval_in_secs = Timescaledb.transform_interval(interval).secs

    case rem(interval_in_secs, 86400) do
      0 ->
        calculate_token_circulation(
          :less_than_a_day,
          contract,
          from,
          to,
          interval,
          token_decimals
        )

      _ ->
        {:error, "The interval must consist of whole days"}
    end
  end

  @doc ~s"""
  Return the token circulation for a given contract and time restrictions.
  Currently supports only the token circulation for less than a day.
  """
  @spec token_circulation(
          :less_than_a_day,
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: list(circulation_map) | no_return
  def token_circulation!(:less_than_a_day, contract, from, to, interval, token_decimals \\ 0) do
    case token_circulation(:less_than_a_day, contract, from, to, interval, token_decimals) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def first_datetime(contract) do
    "FROM #{@table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end

  # Private functions

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
end
