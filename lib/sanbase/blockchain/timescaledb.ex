defmodule Sanbase.Timescaledb do
  defmacro time_bucket(interval) do
    quote do
      # , unquote(interval))
      fragment("time_bucket('35 days', timestamp) as san_internal_time_bucket")
    end
  end

  defmacro time_bucket() do
    quote do
      fragment("san_internal_time_bucket")
    end
  end

  defmacro coalesce(left, right) do
    quote do
      fragment("coalesce(?, ?)", unquote(left), unquote(right))
    end
  end
end
