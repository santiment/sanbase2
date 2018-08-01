defmodule Sanbase.Timescaledb do
  defmacro time_bucket(interval) do
    quote do
      fragment(
        "time_bucket(?::interval, timestamp) as dt",
        unquote(interval)
      )
    end
  end

  defmacro time_bucket() do
    quote do
      fragment("time_bucket")
    end
  end

  defmacro coalesce(left, right) do
    quote do
      fragment("coalesce(?, ?)", unquote(left), unquote(right))
    end
  end

  defmacro generate_series(from, to, interval) do
    quote do
      fragment(
        """
        select generate_series(?, ?, ?::interval)::timestamp AS d
        """,
        unquote(from),
        unquote(to),
        unquote(interval)
      )
    end
  end
end
