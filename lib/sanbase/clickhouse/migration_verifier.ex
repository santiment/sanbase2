defmodule Sanbase.Clickhouse.MigrationVerifier do
  @moduledoc """
  Verification module for the clickhousex → ch/ecto_ch migration.

  Run `MigrationVerifier.verify_all()` in an IEx session connected to a
  real ClickHouse instance to confirm the driver swap works end-to-end.

  Each `verify_*` function returns `{:ok, detail}` or `{:error, reason}`.
  `verify_all/0` runs them all and prints a summary.
  """

  alias Sanbase.ClickhouseRepo

  @doc "SELECT 1 — basic connectivity check"
  def verify_basic_select do
    verify_query("SELECT 1 AS val", %{}, [1], "SELECT 1 returned [1]")
  end

  @doc "String parameter binding"
  def verify_string_param do
    verify_query(
      "SELECT {{str}} AS val",
      %{str: "hello"},
      ["hello"],
      "String param returned 'hello'"
    )
  end

  @doc "Integer parameter binding"
  def verify_integer_param do
    verify_query("SELECT {{num}} AS val", %{num: 42}, [42], "Integer param returned 42")
  end

  @doc "List parameter binding with arrayJoin"
  def verify_list_param do
    verify_query(
      "SELECT arrayJoin({{values}}) AS val ORDER BY val",
      %{values: [1, 2, 3]},
      [1, 2, 3],
      "List param returned [1, 2, 3]"
    )
  end

  @doc "DateTime parameter binding"
  def verify_datetime_param do
    dt = ~U[2024-01-15 12:00:00Z]
    query = Sanbase.Clickhouse.Query.new("SELECT {{dt}} AS val", %{dt: dt})

    case ClickhouseRepo.query_transform(query, fn [val] -> val end) do
      {:ok, [result]} -> {:ok, "DateTime param returned #{inspect(result)}"}
      {:error, err} -> {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Inline parameter (table name substitution)"
  def verify_inline_param do
    verify_query(
      "SELECT count() AS cnt FROM {{table:inline}}",
      %{table: "system.one"},
      [1],
      "Inline param: SELECT count() FROM system.one returned [1]"
    )
  end

  @doc "Explicit type override"
  def verify_type_override do
    verify_query(
      "SELECT {{num:UInt8}} AS val",
      %{num: 255},
      [255],
      "Type override UInt8 returned 255"
    )
  end

  @doc "query_transform_with_metadata returns columns and query_id"
  def verify_metadata do
    query = Sanbase.Clickhouse.Query.new("SELECT 1 AS a, 'test' AS b", %{})

    case ClickhouseRepo.query_transform_with_metadata(query, & &1) do
      {:ok, %{column_names: columns, query_id: query_id, rows: rows}} ->
        checks = [
          columns == ["a", "b"] || {:error, "columns: #{inspect(columns)}"},
          is_binary(query_id) || {:error, "query_id not a string: #{inspect(query_id)}"},
          length(rows) == 1 || {:error, "expected 1 row, got #{length(rows)}"}
        ]

        case Enum.find(checks, &match?({:error, _}, &1)) do
          nil -> {:ok, "Metadata: columns=#{inspect(columns)}, query_id=#{query_id}"}
          {:error, detail} -> {:error, "Metadata check failed: #{detail}"}
        end

      {:error, err} ->
        {:error, "Query failed: #{inspect(err)}"}
    end
  end

  @doc "Error handling for invalid SQL"
  def verify_error_handling do
    query = Sanbase.Clickhouse.Query.new("SELECTTTT INVALID SYNTAX", %{})

    case ClickhouseRepo.query_transform(query, & &1) do
      {:error, error_msg} when is_binary(error_msg) ->
        {:ok, "Error handling works, got error: #{String.slice(error_msg, 0, 80)}..."}

      {:ok, _} ->
        {:error, "Expected error for invalid SQL, but got success"}
    end
  end

  @doc "Run all verification checks and print a summary"
  def verify_all do
    checks = [
      {"basic_select", &verify_basic_select/0},
      {"string_param", &verify_string_param/0},
      {"integer_param", &verify_integer_param/0},
      {"list_param", &verify_list_param/0},
      {"datetime_param", &verify_datetime_param/0},
      {"inline_param", &verify_inline_param/0},
      {"type_override", &verify_type_override/0},
      {"metadata", &verify_metadata/0},
      {"error_handling", &verify_error_handling/0}
    ]

    results =
      Enum.map(checks, fn {name, fun} ->
        result =
          try do
            fun.()
          rescue
            e -> {:error, "Exception: #{Exception.message(e)}"}
          end

        {name, result}
      end)

    IO.puts("\n=== ClickHouse Migration Verification ===\n")

    Enum.each(results, fn {name, result} ->
      status =
        case result do
          {:ok, detail} -> "PASS  #{detail}"
          {:error, reason} -> "FAIL  #{reason}"
        end

      IO.puts("  [#{name}] #{status}")
    end)

    passed = Enum.count(results, fn {_, r} -> match?({:ok, _}, r) end)
    failed = Enum.count(results, fn {_, r} -> match?({:error, _}, r) end)

    IO.puts("\n  #{passed} passed, #{failed} failed out of #{length(results)} checks\n")

    if failed == 0, do: :ok, else: {:error, "#{failed} checks failed"}
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
end
