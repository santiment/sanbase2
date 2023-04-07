defmodule Sanbase.Clickhouse.MetricAdapter.TableMetric do
  import Sanbase.Clickhouse.MetricAdapter.TableSqlQuery
  import Sanbase.Utils.Transform

  alias Sanbase.ClickhouseRepo

  def table_data(_metric, %{slug: []}, _from, _to) do
    {:ok,
     %{
       rows: [],
       columns: [],
       values: []
     }}
  end

  def table_data(
        "labelled_exchange_balance_sum" = metric,
        %{slug: slug_or_slugs},
        from,
        to,
        _opts
      ) do
    slugs = List.wrap(slug_or_slugs)
    query_struct = table_data_query(metric, slugs, from, to)

    ClickhouseRepo.query_transform(query_struct, fn [_label | tail] -> tail end)
    |> maybe_apply_function(&transform_table_data(&1, slugs))
  end

  # Private functiions

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
