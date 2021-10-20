defmodule SanbaseWeb.Graphql.CustomTypes.DateTime do
  use Absinthe.Schema.Notation

  scalar :datetime, name: "DateTime" do
    description("""
    The `DateTime` scalar type represents a date and time in the UTC
    timezone. The DateTime appears in a JSON response as an ISO8601 formatted
    string, including UTC timezone ("Z"). The parsed date and time string will
    be converted to UTC and any UTC offset other than 0 will be rejected.
    """)

    serialize(fn
      %NaiveDateTime{} = ndt ->
        DateTime.from_naive!(ndt, "Etc/UTC")
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      %DateTime{} = dt ->
        dt
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
    end)

    parse(&parse_datetime/1)
  end

  scalar :naive_datetime, name: "NaiveDateTime" do
    description("""
    The `Naive DateTime` scalar type represents a naive date and time without
    timezone. The DateTime appears in a JSON response as an ISO8601 formatted
    string.
    """)

    serialize(&NaiveDateTime.to_iso8601/1)
    parse(&parse_naive_datetime/1)
  end

  scalar :time do
    description("""
    The `Time` scalar type represents a time. The Time appears in a JSON
    response as an ISO8601 formatted string, without a date component.
    """)

    serialize(&Time.to_iso8601/1)
    parse(&parse_time/1)
  end

  @spec parse_datetime(Absinthe.Blueprint.Input.String.t()) :: {:ok, DateTime.t()} | :error
  @spec parse_datetime(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp parse_datetime(%Absinthe.Blueprint.Input.String{value: "utc_now" <> _rest = value}) do
    case Sanbase.DateTimeUtils.utc_now_string_to_datetime(value) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> :error
    end
  end

  defp parse_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} -> {:ok, datetime}
      {:ok, _datetime, _offset} -> :error
      _error -> :error
    end
  end

  defp parse_datetime(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp parse_datetime(_) do
    :error
  end

  @spec parse_naive_datetime(Absinthe.Blueprint.Input.String.t()) ::
          {:ok, NaiveDateTime.t()} | :error
  @spec parse_naive_datetime(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp parse_naive_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive_datetime} -> {:ok, naive_datetime}
      _error -> :error
    end
  end

  defp parse_naive_datetime(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp parse_naive_datetime(_) do
    :error
  end

  @spec parse_time(Absinthe.Blueprint.Input.String.t()) :: {:ok, Time.t()} | :error
  @spec parse_time(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp parse_time(%Absinthe.Blueprint.Input.String{value: value}) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      _error -> :error
    end
  end

  defp parse_time(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp parse_time(_) do
    :error
  end
end
