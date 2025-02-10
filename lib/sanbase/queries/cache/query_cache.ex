defmodule Sanbase.Queries.QueryCache do
  @moduledoc false
  alias Sanbase.Queries.Executor.Result

  @type t :: %__MODULE__{
          query_id: String.t(),
          dashboard_query_mapping_id: non_neg_integer(),
          clickhouse_query_id: String.t(),
          dashboard_id: non_neg_integer(),
          columns: list(String.t()),
          column_types: list(String.t()),
          rows: List.t(),
          compressed_rows: String.t(),
          updated_at: DateTime.t(),
          query_start_time: DateTime.t(),
          query_end_time: DateTime.t(),
          summary: String.t()
        }

  defstruct query_id: nil,
            dashboard_query_mapping_id: nil,
            clickhouse_query_id: nil,
            dashboard_id: nil,
            columns: nil,
            column_types: nil,
            rows: nil,
            compressed_rows: nil,
            updated_at: nil,
            query_start_time: nil,
            query_end_time: nil,
            summary: nil

  @spec from_query_result(Result.t(), String.t(), non_neg_integer()) :: t()
  def from_query_result(%Result{} = result, dashboard_query_mapping_id, dashboard_id) do
    compressed_rows =
      if is_nil(result.compressed_rows) do
        Result.compress_rows(result.rows)
      else
        result.compressed_rows
      end

    %__MODULE__{
      query_id: result.query_id,
      dashboard_query_mapping_id: dashboard_query_mapping_id,
      dashboard_id: dashboard_id,
      columns: result.columns,
      column_types: result.column_types,
      rows: result.rows,
      compressed_rows: compressed_rows,
      updated_at: DateTime.utc_now(),
      query_start_time: result.query_start_time,
      query_end_time: result.query_end_time,
      clickhouse_query_id: result.clickhouse_query_id,
      summary: result.summary
    }
  end
end
