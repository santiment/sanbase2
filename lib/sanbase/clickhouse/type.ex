defmodule Sanbase.Clickhouse.Type do
  @moduledoc """
  Infer ClickHouse types from Elixir values for use with the `ch` driver's
  typed placeholder syntax `{$N:Type}`.

  The inference rules mirror `ecto_ch`'s `param_type/1`.

  The `@known_ch_types` allowlist controls which type names are recognized for
  the `{{key:Type}}` override syntax. This is intentionally not a blocklist so
  that typos like `{{key:huamn_readable}}` are caught at template expansion time
  rather than silently treated as a CH type.
  """

  @max_int32 Integer.pow(2, 31) - 1
  @max_int64 Integer.pow(2, 63) - 1
  @max_uint64 Integer.pow(2, 64) - 1
  @max_uint128 Integer.pow(2, 128) - 1
  @max_uint256 Integer.pow(2, 256) - 1

  @min_int32 -Integer.pow(2, 31)
  @min_int64 -Integer.pow(2, 63)
  @min_int128 -Integer.pow(2, 127)
  @min_int256 -Integer.pow(2, 255)

  @known_ch_types MapSet.new(~w(
    UInt8 UInt16 UInt32 UInt64 UInt128 UInt256
    Int8 Int16 Int32 Int64 Int128 Int256
    Float32 Float64
    Decimal32 Decimal64 Decimal128 Decimal256
    Bool String FixedString LowCardinality
    Date Date32 DateTime DateTime64
    UUID IPv4 IPv6
    Enum8 Enum16
    Nullable Nothing
    Array Map Tuple Nested
    SimpleAggregateFunction AggregateFunction
    JSON Object
  ))

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
      "Int32"

      iex> Sanbase.Clickhouse.Type.infer(1.5) |> IO.iodata_to_binary()
      "Float64"

      iex> Sanbase.Clickhouse.Type.infer(true) |> IO.iodata_to_binary()
      "Bool"
  """
  @spec infer(term()) :: iodata()
  def infer(s) when is_binary(s), do: "String"

  def infer(b) when is_boolean(b), do: "Bool"

  def infer(i) when is_integer(i) and i >= 0 do
    cond do
      i <= @max_int32 -> "Int32"
      i <= @max_int64 -> "Int64"
      i <= @max_uint64 -> "UInt64"
      i <= @max_uint128 -> "UInt128"
      i <= @max_uint256 -> "UInt256"
      true -> raise ArgumentError, "Integer #{i} exceeds ClickHouse UInt256 maximum"
    end
  end

  def infer(i) when is_integer(i) and i < 0 do
    cond do
      i >= @min_int32 -> "Int32"
      i >= @min_int64 -> "Int64"
      i >= @min_int128 -> "Int128"
      i >= @min_int256 -> "Int256"
      true -> raise ArgumentError, "Integer #{i} exceeds ClickHouse Int256 minimum"
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

    decimal_type =
      cond do
        scale <= 9 -> "Decimal32"
        scale <= 18 -> "Decimal64"
        scale <= 38 -> "Decimal128"
        scale <= 76 -> "Decimal256"
        true -> raise ArgumentError, "Decimal scale #{scale} is not supported in ClickHouse"
      end

    [decimal_type, "(", Integer.to_string(scale), ?)]
  end

  def infer([]), do: "Array(Nothing)"

  def infer([first | rest]) do
    el_type = infer(first) |> IO.iodata_to_binary()

    Enum.each(rest, fn elem ->
      elem_type = infer(elem) |> IO.iodata_to_binary()

      if elem_type != el_type do
        raise ArgumentError,
              "Mixed element types in Array: expected #{el_type}, got #{elem_type}"
      end
    end)

    ["Array(", el_type, ?)]
  end

  def infer(%{__struct__: s}) do
    raise ArgumentError, "struct #{inspect(s)} is not supported in params"
  end

  def infer(m) when is_map(m) do
    case Map.to_list(m) do
      [{k, v} | rest] ->
        key_type = infer(k) |> IO.iodata_to_binary()
        val_type = infer(v) |> IO.iodata_to_binary()

        Enum.each(rest, fn {rk, rv} ->
          rk_type = infer(rk) |> IO.iodata_to_binary()
          rv_type = infer(rv) |> IO.iodata_to_binary()

          if rk_type != key_type do
            raise ArgumentError,
                  "Mixed key types in Map: expected #{key_type}, got #{rk_type}"
          end

          if rv_type != val_type do
            raise ArgumentError,
                  "Mixed value types in Map: expected #{val_type}, got #{rv_type}"
          end
        end)

        ["Map(", key_type, ?,, val_type, ?)]

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
