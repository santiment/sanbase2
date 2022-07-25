defmodule Sanbase.Dashboard.Query.Result do
  @moduledoc ~s"""
  The result of computing a dashboard panel SQL query.
  """

  @type t :: %__MODULE__{
          san_query_id: String.t(),
          clickhouse_query_id: String.t(),
          summary: Map.t(),
          rows: list(String.t() | number() | boolean() | DateTime.t()),
          compressed_rows: String.t(),
          columns: list(String.t()),
          column_types: list(String.t()),
          query_start_time: DateTime.t(),
          query_end_time: DateTime.t()
        }

  defstruct san_query_id: nil,
            clickhouse_query_id: nil,
            summary: nil,
            rows: nil,
            compressed_rows: nil,
            columns: nil,
            column_types: nil,
            query_start_time: nil,
            query_end_time: nil
end
