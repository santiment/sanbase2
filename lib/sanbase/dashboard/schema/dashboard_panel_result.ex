defmodule Sanbase.Dashboard.Panel.Result do
  @moduledoc ~s"""
  The result of computing a dashboard panel SQL
  """

  @type t :: %__MODULE__{
          query_id: String.t(),
          panel_id: String.t(),
          dashboard_id: non_neg_integer(),
          summary_json: String.t(),
          rows: list(String.t() | number() | boolean() | DateTime.t()),
          rows_json: String.t(),
          columns: list(String.t()),
          query_start: DateTime.t(),
          query_end: DateTime.t()
        }
  defstruct query_id: nil,
            panel_id: nil,
            dashboard_id: nil,
            summary_json: nil,
            rows: nil,
            rows_json: nil,
            columns: nil,
            query_start: nil,
            query_end: nil
end
