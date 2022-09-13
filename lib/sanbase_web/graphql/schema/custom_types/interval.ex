defmodule SanbaseWeb.Graphql.CustomTypes.Interval do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  scalar :interval, name: "interval" do
    description("""
    The `interval` scalar type represents arbitrary time range interval,
    represented as UTF-8 character sequences (string). The interval starts
    with a number and ends with one of the following suffixes:
    - s - represents second
    - m - represents minute
    - h - represents hour
    - d - represents day
    - w - represents week

    There is no predefined suffix for a month due to not fixed number of days
    a month can have.

    Examples for valid intervals:
    - 5m - 5 minutes
    - 12h - 12 hours
    - 1d - 1 day
    - 30d - 30 days
    - 2w - 2 weeks
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @supported_interval_functions Sanbase.Metric.SqlQuery.Helper.supported_interval_functions()

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: ""}), do: {:ok, ""}

  defp decode(%Absinthe.Blueprint.Input.String{value: value})
       when value in @supported_interval_functions do
    {:ok, value}
  end

  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    case Sanbase.DateTimeUtils.valid_compound_duration?(value) do
      true -> {:ok, value}
      _ -> :error
    end
  end

  defp decode(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value), do: value
end
