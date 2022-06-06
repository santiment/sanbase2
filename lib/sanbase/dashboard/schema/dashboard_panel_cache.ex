defmodule Sanbase.Dashboard.Panel.Cache do
  @type t :: %__MODULE__{
          id: String.t(),
          san_query_id: String.t(),
          clickhouse_query_id: String.t(),
          dashboard_id: non_neg_integer(),
          column_names: list(String.t()),
          rows: String.t(),
          updated_at: DateTime.t(),
          query_start_time: DateTime.t(),
          query_end_time: DateTime.t(),
          summary: String.t()
        }

  defstruct id: nil,
            san_query_id: nil,
            clickhouse_query_id: nil,
            dashboard_id: nil,
            column_names: nil,
            rows: nil,
            updated_at: nil,
            query_start_time: nil,
            query_end_time: nil,
            summary: nil

  alias Sanbase.Dashboard.Query

  @spec from_query_result(Query.Result.t(), String.t(), non_neg_integer()) :: t()
  def from_query_result(%Query.Result{} = result, panel_id, dashboard_id) do
    %{
      id: panel_id,
      dashboard_id: dashboard_id,
      column_names: result.columns,
      rows: result.rows,
      updated_at: DateTime.utc_now(),
      query_start_time: result.query_start_time,
      query_end_time: result.query_end_time,
      san_query_id: result.san_query_id,
      clickhouse_query_id: result.clickhouse_query_id,
      summary: result.summary
    }
  end
end
