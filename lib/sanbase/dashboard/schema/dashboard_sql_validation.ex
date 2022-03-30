defmodule Sanbase.Dashboard.SqlValidation do
  @validation_functions [:from_clauses]
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

  @allowed_tables [
    "asset_metadata",
    "asset_prices",
    "intraday_metrics",
    "daily_metrics_v2",
    "numbers"
  ]

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
