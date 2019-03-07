defmodule Sanbase.Clickhouse.Common do
  alias Sanbase.DateTimeUtils

  def datetime_rounding_for_interval(interval) do
    if interval < DateTimeUtils.compound_duration_to_seconds("1d") do
      "toStartOfHour(dt)"
    else
      "toStartOfDay(dt)"
    end
  end
end
