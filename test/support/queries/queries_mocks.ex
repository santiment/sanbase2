defmodule Sanbase.QueriesMocks do
  @moduledoc false
  def mocked_clickhouse_result(slug \\ "bitcoin") do
    %Clickhousex.Result{
      columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
      column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
      command: :selected,
      num_rows: 2,
      query_id: "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
      rows: [
        [slug, 250, ~N[2008-12-10 00:00:00], +0.0, ~N[2020-02-28 15:18:42]],
        [slug, 250, ~N[2008-12-10 00:05:00], +0.0, ~N[2020-02-28 15:18:42]]
      ],
      summary: %{
        "read_bytes" => "0",
        "read_rows" => "0",
        "total_rows_to_read" => "0",
        "written_bytes" => "0",
        "written_rows" => "0"
      }
    }
  end

  def mocked_execution_details_result do
    %Clickhousex.Result{
      query_id: "1774C4BC91E058D4",
      summary: %{
        "read_bytes" => "5069080",
        "read_rows" => "167990",
        "result_bytes" => "0",
        "result_rows" => "0",
        "total_rows_to_read" => "167990",
        "written_bytes" => "0",
        "written_rows" => "0"
      },
      command: :selected,
      columns: [
        "read_compressed_gb",
        "cpu_time_microseconds",
        "query_duration_ms",
        "memory_usage_gb",
        "read_rows",
        "read_gb",
        "result_rows",
        "result_gb"
      ],
      column_types: [
        "Float64",
        "UInt64",
        "UInt64",
        "Float64",
        "UInt64",
        "Float64",
        "UInt64",
        "Float64"
      ],
      rows: [
        [
          # read_compressed_gb
          0.001110738143324852,
          # cpu_time_microseconds
          101_200,
          # query_duration_ms
          47,
          # memory_usage_gb
          0.03739274851977825,
          # read_rows
          364_923,
          # read_gb
          0.01087852381169796,
          # result_rows
          2,
          # result_gb
          2.980232238769531e-7
        ]
      ],
      num_rows: 1
    }
  end
end
