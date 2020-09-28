defmodule Sanbase.Clickhouse.Metric.TableMetric do
  import Sanbase.Clickhouse.Metric.SqlQuery

  alias Sanbase.ClickhouseRepo

  def table_data(_metric, %{slug: []}, _from, _to), do: {:ok, []}

  def table_data("labelled_exchange_balance_sum", %{slug: slug_or_slugs}, from, to) do
    slugs = List.wrap(slug_or_slugs)
    {query, args} = table_data_query("labelled_exchange_balance_sum", slugs, from, to)

    case ClickhouseRepo.query_transform(query, args, fn [_label | tail] -> tail end) do
      {:ok, owner_value_pairs} -> {:ok, transform_table_data(owner_value_pairs, slugs)}
      {:error, error} -> {:error, error}
    end
  end

  defp transform_table_data(owner_value_pairs, slugs) do
    rows = Enum.map(owner_value_pairs, fn [owner | _values] -> owner end)

    values =
      Enum.map(owner_value_pairs, fn [_owner | values] -> values end)
      |> List.flatten()
      |> Enum.chunk_every(length(slugs))

    %{
      rows: rows,
      columns: slugs,
      values: values
    }
  end
end
