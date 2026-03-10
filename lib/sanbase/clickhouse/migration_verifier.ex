defmodule Sanbase.Clickhouse.MigrationVerifier do
  @moduledoc """
  Verification module for the clickhousex → ch/ecto_ch migration.

  Run `MigrationVerifier.verify_all()` in an IEx session connected to a
  real ClickHouse instance to confirm the driver swap works end-to-end.

  Each `verify_*` function returns `{:ok, detail}` or `{:error, reason}`.
  `verify_all/0` runs them all and prints a summary.
  """

  alias Sanbase.ClickhouseRepo

  @type verify_result :: {:ok, String.t()} | {:error, String.t()}

  @doc "SELECT 1 — basic connectivity check"
  @spec verify_basic_select() :: verify_result()
  def verify_basic_select do
    verify_query("SELECT 1 AS val", %{}, [1], "SELECT 1 returned [1]")
  end

  @doc "String parameter binding"
  @spec verify_string_param() :: verify_result()
  def verify_string_param do
    verify_query(
      "SELECT {{str}} AS val",
      %{str: "hello"},
      ["hello"],
      "String param returned 'hello'"
    )
  end

  @doc "Integer parameter binding"
  @spec verify_integer_param() :: verify_result()
  def verify_integer_param do
    verify_query("SELECT {{num}} AS val", %{num: 42}, [42], "Integer param returned 42")
  end

  @doc "List parameter binding with arrayJoin"
  @spec verify_list_param() :: verify_result()
  def verify_list_param do
    verify_query(
      "SELECT arrayJoin({{values}}) AS val ORDER BY val",
      %{values: [1, 2, 3]},
      [1, 2, 3],
      "List param returned [1, 2, 3]"
    )
  end

  @doc "Reused parameter keeps one bound value across placeholders"
  @spec verify_reused_param() :: verify_result()
  def verify_reused_param do
    verify_query(
      "SELECT if({{slug}} = {{slug}}, {{slug}}, 'mismatch') AS val",
      %{slug: "bitcoin"},
      ["bitcoin"],
      "Reused param returned 'bitcoin'"
    )
  end

  @doc "Nullable parameter binding"
  @spec verify_nil_param() :: verify_result()
  def verify_nil_param do
    verify_query(
      "SELECT CAST(isNull({{value}}) AS Bool) AS val",
      %{value: nil},
      [true],
      "Nullable param returned true for isNull()"
    )
  end

  @doc "Array type override for mixed-width integers"
  @spec verify_array_type_override() :: verify_result()
  def verify_array_type_override do
    verify_query(
      "SELECT arrayJoin({{values:Array(Int64)}}) AS val ORDER BY val",
      %{values: [2_147_483_647, 2_147_483_648]},
      [2_147_483_647, 2_147_483_648],
      "Array(Int64) override returned mixed-width integers"
    )
  end

  @doc "DateTime parameter binding"
  @spec verify_datetime_param() :: verify_result()
  def verify_datetime_param do
    dt = ~U[2024-01-15 12:00:00Z]
    # ch driver returns ClickHouse DateTime as NaiveDateTime (no timezone info)
    expected = ~N[2024-01-15 12:00:00]
    query = Sanbase.Clickhouse.Query.new("SELECT {{dt}} AS val", %{dt: dt})

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, [^expected]} -> {:ok, "DateTime param returned #{inspect(expected)}"}
      {:ok, [other]} -> {:error, "Expected #{inspect(expected)}, got #{inspect(other)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Inline parameter (table name substitution)"
  @spec verify_inline_param() :: verify_result()
  def verify_inline_param do
    verify_query(
      "SELECT count() AS cnt FROM {{table:inline}}",
      %{table: "system.one"},
      [1],
      "Inline param: SELECT count() FROM system.one returned [1]"
    )
  end

  @doc "Explicit type override"
  @spec verify_type_override() :: verify_result()
  def verify_type_override do
    verify_query(
      "SELECT {{num:UInt8}} AS val",
      %{num: 255},
      [255],
      "Type override UInt8 returned 255"
    )
  end

  @doc "query_transform_with_metadata returns columns, types, query_id and summary"
  @spec verify_metadata() :: verify_result()
  def verify_metadata do
    query = Sanbase.Clickhouse.Query.new("SELECT 1 AS a, 'test' AS b", %{})

    case ClickhouseRepo.query_transform_with_metadata(query, & &1) do
      {:ok,
       %{
         column_names: columns,
         column_types: column_types,
         query_id: query_id,
         rows: rows,
         summary: summary
       }} ->
        checks = [
          columns == ["a", "b"] ||
            {:error, "columns: expected [\"a\", \"b\"], got #{inspect(columns)}"},
          (is_list(column_types) and length(column_types) == 2) ||
            {:error, "column_types: expected list of 2 types, got #{inspect(column_types)}"},
          (is_list(column_types) and Enum.all?(column_types, &is_binary/1)) ||
            {:error, "column_types: expected all string types, got #{inspect(column_types)}"},
          (is_binary(query_id) and byte_size(query_id) > 0) ||
            {:error, "query_id: expected non-empty string, got #{inspect(query_id)}"},
          is_map(summary) ||
            {:error, "summary: expected a map, got #{inspect(summary)}"},
          rows == [[1, "test"]] ||
            {:error, "rows: expected [[1, \"test\"]], got #{inspect(rows)}"}
        ]

        case Enum.find(checks, &match?({:error, _}, &1)) do
          nil ->
            {:ok,
             "Metadata: columns=#{inspect(columns)}, types=#{inspect(column_types)}, query_id=#{query_id}"}

          {:error, detail} ->
            {:error, "Metadata check failed: #{detail}"}
        end

      {:error, err} ->
        {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Error handling for invalid SQL"
  @spec verify_error_handling() :: verify_result()
  def verify_error_handling do
    query = Sanbase.Clickhouse.Query.new("SELECTTTT INVALID SYNTAX", %{})

    # query_transform does not propagate errors, so the error should be
    # a masked message with a UUID prefix: "[<uuid>] Cannot execute database query..."
    case ClickhouseRepo.query_transform(query, & &1) do
      {:error, error_msg} when is_binary(error_msg) ->
        uuid_prefix_pattern =
          ~r/^\[[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\] /

        masked_suffix =
          "Cannot execute database query. If issue persists please contact Santiment Support."

        checks = [
          Regex.match?(uuid_prefix_pattern, error_msg) ||
            {:error, "Error missing UUID prefix: #{inspect(error_msg)}"},
          String.contains?(error_msg, masked_suffix) ||
            {:error, "Error missing masked message, got: #{inspect(error_msg)}"}
        ]

        case Enum.find(checks, &match?({:error, _}, &1)) do
          nil -> {:ok, "Error handling: got UUID-prefixed masked error"}
          {:error, detail} -> {:error, "Error shape check failed: #{detail}"}
        end

      {:error, other} ->
        {:error, "Expected binary error message, got: #{inspect(other)}"}

      {:ok, _} ->
        {:error, "Expected error for invalid SQL, but got success"}
    end
  end

  @doc "Multiple-row result with simple transform"
  @spec verify_multirow_basic() :: verify_result()
  def verify_multirow_basic do
    query =
      Sanbase.Clickhouse.Query.new(
        "SELECT number AS val FROM system.numbers LIMIT 3",
        %{}
      )

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, [0, 1, 2]} -> {:ok, "Multi-row basic select returned [0, 1, 2]"}
      {:ok, other} -> {:error, "Expected [0, 1, 2], got #{inspect(other)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Array parameter used for filtering values"
  @spec verify_array_filter_param() :: verify_result()
  def verify_array_filter_param do
    verify_query(
      "SELECT arrayJoin({{values}}) AS v WHERE v > 1 ORDER BY v",
      %{values: [1, 2, 3]},
      [2, 3],
      "Array filter param returned [2, 3]"
    )
  end

  @doc "query_transform on a multi-column result"
  @spec verify_multi_column_transform() :: verify_result()
  def verify_multi_column_transform do
    query =
      Sanbase.Clickhouse.Query.new(
        "SELECT number AS n, number * 2 AS doubled FROM system.numbers LIMIT 3",
        %{}
      )

    case ClickhouseRepo.query_transform(query, fn [n, doubled] -> {n, doubled} end) do
      {:ok, [{0, 0}, {1, 2}, {2, 4}]} ->
        {:ok, "Multi-column transform returned [{0, 0}, {1, 2}, {2, 4}]"}

      {:ok, other} ->
        {:error, "Expected [{0, 0}, {1, 2}, {2, 4}], got #{inspect(other)}"}

      {:error, err} ->
        {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Float parameter binding"
  @spec verify_float_param() :: verify_result()
  def verify_float_param do
    verify_query(
      "SELECT CAST({{val}} AS Float64) AS val",
      %{val: 3.14},
      [3.14],
      "Float param returned 3.14"
    )
  end

  @doc "String with special characters"
  @spec verify_special_chars_string() :: verify_result()
  def verify_special_chars_string do
    verify_query(
      "SELECT {{str}} AS val",
      %{str: "it's a \"test\" with \\ backslash"},
      ["it's a \"test\" with \\ backslash"],
      "Special chars string preserved correctly"
    )
  end

  @doc "Empty string parameter"
  @spec verify_empty_string() :: verify_result()
  def verify_empty_string do
    verify_query(
      "SELECT {{str}} AS val",
      %{str: ""},
      [""],
      "Empty string param returned ''"
    )
  end

  @doc "Large integer parameter (UInt64 range)"
  @spec verify_large_integer() :: verify_result()
  def verify_large_integer do
    big = 9_223_372_036_854_775_807

    verify_query(
      "SELECT {{num}} AS val",
      %{num: big},
      [big],
      "Large Int64 max returned correctly"
    )
  end

  @doc "Negative integer parameter"
  @spec verify_negative_integer() :: verify_result()
  def verify_negative_integer do
    verify_query("SELECT {{num}} AS val", %{num: -42}, [-42], "Negative integer returned -42")
  end

  @doc "Empty array parameter"
  @spec verify_empty_array() :: verify_result()
  def verify_empty_array do
    query = Sanbase.Clickhouse.Query.new("SELECT length({{arr:Array(Int32)}}) AS val", %{arr: []})

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, [0]} -> {:ok, "Empty array has length 0"}
      {:ok, other} -> {:error, "Expected [0], got #{inspect(other)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Multiple parameters of different types in one query"
  @spec verify_mixed_param_types() :: verify_result()
  def verify_mixed_param_types do
    query =
      Sanbase.Clickhouse.Query.new(
        "SELECT {{str}} AS s, {{num}} AS n, CAST({{flag}} AS Bool) AS b",
        %{str: "hello", num: 42, flag: true}
      )

    case ClickhouseRepo.query_transform(query, fn row -> row end) do
      {:ok, [["hello", 42, true]]} ->
        {:ok, "Mixed types: string='hello', int=42, bool=true"}

      {:ok, other} ->
        {:error, "Expected [['hello', 42, true]], got #{inspect(other)}"}

      {:error, err} ->
        {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Date parameter binding"
  @spec verify_date_param() :: verify_result()
  def verify_date_param do
    date = ~D[2024-06-15]
    query = Sanbase.Clickhouse.Query.new("SELECT {{d}} AS val", %{d: date})

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, [result]} -> {:ok, "Date param returned #{inspect(result)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Decimal parameter binding"
  @spec verify_decimal_param() :: verify_result()
  def verify_decimal_param do
    dec = Decimal.new("123.45")
    query = Sanbase.Clickhouse.Query.new("SELECT {{d}} AS val", %{d: dec})

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, [result]} -> {:ok, "Decimal param returned #{inspect(result)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "query_reduce aggregation"
  @spec verify_query_reduce() :: verify_result()
  def verify_query_reduce do
    query =
      Sanbase.Clickhouse.Query.new(
        "SELECT number AS val FROM system.numbers LIMIT 5",
        %{}
      )

    case ClickhouseRepo.query_reduce(query, 0, fn [val], acc -> acc + val end) do
      {:ok, 10} -> {:ok, "query_reduce summed 0..4 = 10"}
      {:ok, other} -> {:error, "Expected 10, got #{inspect(other)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Empty result set returns empty list"
  @spec verify_empty_result() :: verify_result()
  def verify_empty_result do
    verify_query(
      "SELECT number AS val FROM system.numbers WHERE number > 100 LIMIT 0",
      %{},
      [],
      "Empty result set returned []"
    )
  end

  # -- Sanbase.Metric integration checks --
  # Use daily_active_addresses for bitcoin — a pure ClickHouse on-chain metric
  # that bypasses SocialData/MetricsHub/Price adapters.

  @metric "daily_active_addresses"
  @selector %{slug: "bitcoin"}

  @doc "Sanbase.Metric.timeseries_data returns data points with datetime and value"
  @spec verify_metric_timeseries_data() :: verify_result()
  def verify_metric_timeseries_data do
    to = DateTime.utc_now()
    from = DateTime.add(to, -7, :day)

    case Sanbase.Metric.timeseries_data(@metric, @selector, from, to, "1d") do
      {:ok, [%{datetime: %DateTime{}, value: v} | _] = data} when is_number(v) ->
        {:ok, "timeseries_data returned #{length(data)} data points"}

      {:ok, []} ->
        {:error, "timeseries_data returned empty list for #{@metric}/bitcoin in last 7 days"}

      {:ok, [first | _]} ->
        {:error, "Unexpected data point shape: #{inspect(first)}"}

      {:error, err} ->
        {:error, "timeseries_data failed: #{inspect(err)}"}
    end
  end

  @doc "Sanbase.Metric.aggregated_timeseries_data returns a map with slug keys"
  @spec verify_metric_aggregated_timeseries_data() :: verify_result()
  def verify_metric_aggregated_timeseries_data do
    to = DateTime.utc_now()
    from = DateTime.add(to, -7, :day)

    case Sanbase.Metric.aggregated_timeseries_data(@metric, @selector, from, to) do
      {:ok, %{"bitcoin" => value}} when is_number(value) ->
        {:ok, "aggregated_timeseries_data returned bitcoin=#{value}"}

      {:ok, %{"bitcoin" => nil}} ->
        {:error, "aggregated_timeseries_data returned nil for bitcoin"}

      {:ok, other} ->
        {:error, "Unexpected result shape: #{inspect(other)}"}

      {:error, err} ->
        {:error, "aggregated_timeseries_data failed: #{inspect(err)}"}
    end
  end

  @doc "Sanbase.Metric.timeseries_data_per_slug returns per-slug data points"
  @spec verify_metric_timeseries_data_per_slug() :: verify_result()
  def verify_metric_timeseries_data_per_slug do
    to = DateTime.utc_now()
    from = DateTime.add(to, -7, :day)
    selector = %{slug: ["bitcoin", "ethereum"]}

    case Sanbase.Metric.timeseries_data_per_slug(@metric, selector, from, to, "1d") do
      {:ok, [%{datetime: %DateTime{}, data: [%{slug: s, value: v} | _]} | _] = data}
      when is_binary(s) and is_number(v) ->
        {:ok, "timeseries_data_per_slug returned #{length(data)} data points"}

      {:ok, []} ->
        {:error, "timeseries_data_per_slug returned empty list"}

      {:ok, [first | _]} ->
        {:error, "Unexpected data point shape: #{inspect(first)}"}

      {:error, err} ->
        {:error, "timeseries_data_per_slug failed: #{inspect(err)}"}
    end
  end

  @doc "Sanbase.Metric.first_datetime returns a DateTime for a known metric/slug"
  @spec verify_metric_first_datetime() :: verify_result()
  def verify_metric_first_datetime do
    case Sanbase.Metric.first_datetime(@metric, @selector, []) do
      {:ok, %DateTime{} = dt} ->
        {:ok, "first_datetime returned #{DateTime.to_iso8601(dt)}"}

      {:ok, other} ->
        {:error, "Expected DateTime, got: #{inspect(other)}"}

      {:error, err} ->
        {:error, "first_datetime failed: #{inspect(err)}"}
    end
  end

  @doc "Run all verification checks and print a summary"
  @spec verify_all() :: {:ok, :all_checks_passed} | {:error, String.t()}
  def verify_all do
    results =
      Enum.map(checks(), fn {name, fun} ->
        result =
          try do
            fun.()
          rescue
            e -> {:error, "Exception: #{Exception.message(e)}"}
          end

        {name, result}
      end)

    IO.puts(IO.ANSI.format([:bright, "\n=== ClickHouse Migration Verification ===\n"]))

    Enum.each(results, fn {name, result} ->
      line =
        case result do
          {:ok, detail} -> IO.ANSI.format([:green, "  PASS  ", :reset, "[#{name}] #{detail}"])
          {:error, reason} -> IO.ANSI.format([:red, "  FAIL  ", :reset, "[#{name}] #{reason}"])
        end

      IO.puts(line)
    end)

    passed = Enum.count(results, fn {_, r} -> match?({:ok, _}, r) end)
    failed = Enum.count(results, fn {_, r} -> match?({:error, _}, r) end)

    summary =
      if failed == 0 do
        IO.ANSI.format([
          :green,
          "\n  #{passed} passed, #{failed} failed out of #{length(results)} checks\n"
        ])
      else
        IO.ANSI.format([
          :red,
          "\n  #{passed} passed, #{failed} failed out of #{length(results)} checks\n"
        ])
      end

    IO.puts(summary)

    if failed == 0, do: {:ok, :all_checks_passed}, else: {:error, "#{failed} checks failed"}
  end

  # Shared helper for simple single-value-per-row query verification
  defp verify_query(sql, params, expected, success_msg) do
    query = Sanbase.Clickhouse.Query.new(sql, params)

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, ^expected} -> {:ok, success_msg}
      {:ok, other} -> {:error, "Expected #{inspect(expected)}, got #{inspect(other)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  defp checks do
    [
      {"basic_select", &verify_basic_select/0},
      {"string_param", &verify_string_param/0},
      {"special_chars_string", &verify_special_chars_string/0},
      {"empty_string", &verify_empty_string/0},
      {"integer_param", &verify_integer_param/0},
      {"negative_integer", &verify_negative_integer/0},
      {"large_integer", &verify_large_integer/0},
      {"float_param", &verify_float_param/0},
      {"decimal_param", &verify_decimal_param/0},
      {"date_param", &verify_date_param/0},
      {"datetime_param", &verify_datetime_param/0},
      {"nil_param", &verify_nil_param/0},
      {"list_param", &verify_list_param/0},
      {"empty_array", &verify_empty_array/0},
      {"array_type_override", &verify_array_type_override/0},
      {"array_filter_param", &verify_array_filter_param/0},
      {"reused_param", &verify_reused_param/0},
      {"inline_param", &verify_inline_param/0},
      {"type_override", &verify_type_override/0},
      {"mixed_param_types", &verify_mixed_param_types/0},
      {"multirow_basic", &verify_multirow_basic/0},
      {"multi_column_transform", &verify_multi_column_transform/0},
      {"empty_result", &verify_empty_result/0},
      {"query_reduce", &verify_query_reduce/0},
      {"metadata", &verify_metadata/0},
      {"error_handling", &verify_error_handling/0},
      {"metric_timeseries_data", &verify_metric_timeseries_data/0},
      {"metric_aggregated_timeseries_data", &verify_metric_aggregated_timeseries_data/0},
      {"metric_timeseries_data_per_slug", &verify_metric_timeseries_data_per_slug/0},
      {"metric_first_datetime", &verify_metric_first_datetime/0}
    ]
  end
end
