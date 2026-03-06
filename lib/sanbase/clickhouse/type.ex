defmodule Sanbase.Clickhouse.Type do
  @moduledoc """
  Infer ClickHouse types from Elixir values for use with the `ch` driver's
  typed placeholder syntax `{$N:Type}`.

  The inference rules mirror `ecto_ch`'s `param_type/1`.
  """

  @max_uint128 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @max_uint64 0xFFFFFFFFFFFFFFFF
  @max_int64 0x7FFFFFFFFFFFFFFF
  @min_int128 -0x80000000000000000000000000000000
  @min_int64 -0x8000000000000000

  # ClickHouse type names recognized for the `{{key:Type}}` override syntax.
  # This is intentionally an allowlist (not a blocklist) so that typos like
  # `{{key:huamn_readable}}` are caught at template expansion time rather than
  # silently treated as a CH type. Add new types here as needed.
  @known_ch_types MapSet.new([
                    "UInt8",
                    "UInt16",
                    "UInt32",
                    "UInt64",
                    "UInt128",
                    "UInt256",
                    "Int8",
                    "Int16",
                    "Int32",
                    "Int64",
                    "Int128",
                    "Int256",
                    "Float32",
                    "Float64",
                    "Bool",
                    "String",
                    "Date",
                    "Date32",
                    "DateTime",
                    "DateTime64",
                    "Decimal32",
                    "Decimal64",
                    "Decimal128",
                    "Decimal256",
                    "UUID",
                    "IPv4",
                    "IPv6",
                    "Enum8",
                    "Enum16",
                    "FixedString",
                    "LowCardinality",
                    "Nullable",
                    "Array",
                    "Map",
                    "Tuple",
                    "Nothing",
                    "SimpleAggregateFunction",
                    "AggregateFunction",
                    "Nested",
                    "JSON",
                    "Object"
                  ])

  @doc """
  Return `true` if `type_str` is a known ClickHouse type name (or starts with one).

  Used to distinguish type overrides like `{{key:UInt64}}` from modifiers like
  `{{key:human_readable}}`.

  ## Examples

      iex> Sanbase.Clickhouse.Type.known_ch_type?("UInt64")
      true

      iex> Sanbase.Clickhouse.Type.known_ch_type?("Array(String)")
      true

      iex> Sanbase.Clickhouse.Type.known_ch_type?("human_readable")
      false
  """
  @spec known_ch_type?(String.t()) :: boolean()
  def known_ch_type?(type_str) when is_binary(type_str) do
    # Handle parameterized types like "Array(String)", "DateTime64(3)", etc.
    base_type =
      case String.split(type_str, "(", parts: 2) do
        [base | _] -> base
      end

    MapSet.member?(@known_ch_types, base_type)
  end

  @doc """
  Infer the ClickHouse type string for the given Elixir value.

  Returns an iodata-compatible value (string or charlist/list).

  ## Examples

      iex> Sanbase.Clickhouse.Type.infer("hello") |> IO.iodata_to_binary()
      "String"

      iex> Sanbase.Clickhouse.Type.infer(42) |> IO.iodata_to_binary()
      "Int64"

      iex> Sanbase.Clickhouse.Type.infer(1.5) |> IO.iodata_to_binary()
      "Float64"

      iex> Sanbase.Clickhouse.Type.infer(true) |> IO.iodata_to_binary()
      "Bool"
  """
  @spec infer(term()) :: iodata()
  def infer(s) when is_binary(s), do: "String"

  def infer(b) when is_boolean(b), do: "Bool"

  def infer(i) when is_integer(i) do
    cond do
      i > @max_uint128 -> "UInt256"
      i > @max_uint64 -> "UInt128"
      i > @max_int64 -> "UInt64"
      i < @min_int128 -> "Int256"
      i < @min_int64 -> "Int128"
      true -> "Int64"
    end
  end

  def infer(f) when is_float(f), do: "Float64"

  def infer(%s{microsecond: microsecond}) when s in [NaiveDateTime, DateTime] do
    case microsecond do
      {_val, precision} when precision > 0 ->
        ["DateTime64(", Integer.to_string(precision), ?)]

      _ ->
        "DateTime"
    end
  end

  def infer(%Date{}), do: "Date"

  def infer(%Decimal{exp: exp}) do
    scale = if exp < 0, do: abs(exp), else: 0
    ["Decimal64(", Integer.to_string(scale), ?)]
  end

  def infer([]), do: "Array(Nothing)"

  def infer([v | vs]) do
    el_type = infer(v)

    # infer([]) returns the plain string "Array(Nothing)", so direct comparison works
    if el_type != "Array(Nothing)" or vs == [] do
      ["Array(", el_type, ?)]
    else
      infer(vs)
    end
  end

  def infer(%{__struct__: s}) do
    raise ArgumentError, "struct #{inspect(s)} is not supported in params"
  end

  def infer(m) when is_map(m) do
    case Map.keys(m) do
      [k | _] ->
        [v | _] = Map.values(m)
        ["Map(", infer(k), ?,, infer(v), ?)]

      [] ->
        "Map(Nothing,Nothing)"
    end
  end

  def infer(nil) do
    "Nullable(Nothing)"
  end

  def infer(a) when is_atom(a), do: "String"

  def infer(t) when is_tuple(t), do: "String"
end
