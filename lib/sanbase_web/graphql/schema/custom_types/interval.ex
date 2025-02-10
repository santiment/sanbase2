defmodule SanbaseWeb.Graphql.CustomTypes.Interval do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input.Null

  scalar :interval, name: "interval" do
    description("""
    The `interval` scalar type represents arbitrary time range interval,
    represented as UTF-8 character sequences (string). The interval has two
    representations: fixed range time and functions.

    The fixed range interval starts with a number and ends with one of the following suffixes:
    - s - represents second
    - m - represents minute
    - h - represents hour
    - d - represents day
    - w - represents week

    The function-defined interval helps when the interval need to be aligned at a given
    date (start of week - Monday or Sunday) or at not fixed range intervals like months.
    The supported functions are:
    - toStartOfHour
    - toStartOfDay
    - toMonday
    - toStartOfWeek (aligns dates on Sundays)
    - toStartOfMonth
    - toStartOfQuarter
    - toStartOfYear

    More details can be found here: https://academy.santiment.net/glossary/#interval
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @supported_interval_functions Sanbase.Metric.SqlQuery.Helper.supported_interval_functions()

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: ""}), do: {:ok, ""}

  defp decode(%Absinthe.Blueprint.Input.String{value: value}) when value in @supported_interval_functions do
    {:ok, value}
  end

  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    if Sanbase.DateTimeUtils.valid_compound_duration?(value) do
      {:ok, value}
    else
      :error
    end
  end

  defp decode(%Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value), do: value
end
