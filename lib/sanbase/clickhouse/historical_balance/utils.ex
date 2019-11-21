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
      %{has_changed: 0, datetime: dt}, {acc, last_seen} ->
        {[%{balance: last_seen, datetime: dt} | acc], last_seen}

      %{balance: balance, datetime: dt}, {acc, _last_seen} ->
        {[%{balance: balance, datetime: dt} | acc], balance}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def maybe_fill_gaps_last_seen_balance({:ok, values}) do
    result =
      values
      |> Enum.reduce({[], 0}, fn
        %{has_changed: 0, datetime: dt}, {acc, last_seen} ->
          {[%{balance: last_seen, datetime: dt} | acc], last_seen}

        %{balance: balance, datetime: dt}, {acc, _last_seen} ->
          {[%{balance: balance, datetime: dt} | acc], balance}
      end)
      |> elem(0)
      |> Enum.reverse()

    {:ok, result}
  end

  def maybe_fill_gaps_last_seen_balance({:error, error}), do: {:error, error}

  def maybe_update_first_balance({:ok, [%{has_changed: 0} | _] = data}, fun)
      when is_function(fun, 0) do
    case fun.() do
      {:ok, balance} ->
        [first_elem | rest] = data

        result = [%{first_elem | has_changed: 1, balance: balance} | rest]

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  def maybe_update_first_balance({:ok, result}, _function), do: {:ok, result}
  def maybe_update_first_balance({:error, error}, _function), do: {:error, error}

  def maybe_drop_not_needed({:ok, result}, before_datetime) do
    result =
      result
      |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, before_datetime) == :lt end)

    {:ok, result}
  end

  def maybe_drop_not_needed({:error, error}, _before_datetime), do: {:error, error}
end
