defmodule Sanbase.Clickhouse.HistoricalBalance.Utils do
  @type in_type :: %{
          sign: non_neg_integer(),
          balance: float(),
          datetime: DateTime.t()
        }

  @type out_type :: %{
          balance: float(),
          datetime: DateTime.t()
        }

  @doc ~s"""
  Clickhouse fills empty buckets with 0 while we need it filled with the last
  seen value. As the balance changes happen only when a transfer occurs
  then we need to fetch the whole history of changes in order to find the balance
  """
  @spec fill_gaps_last_seen_balance(list(in_type)) :: list(out_type)
  def fill_gaps_last_seen_balance(values) do
    values
    |> Enum.reduce({[], 0}, fn
      %{sign: 1, balance: balance, datetime: dt}, {acc, _last_seen} ->
        {[%{balance: balance, datetime: dt} | acc], balance}

      %{sign: 0, datetime: dt}, {acc, last_seen} ->
        {[%{balance: last_seen, datetime: dt} | acc], last_seen}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
