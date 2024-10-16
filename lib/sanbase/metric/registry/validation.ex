defmodule Sanbase.Metric.Registry.Validation do
  @valid_default_aggregation ["sum", "last", "count", "avg", "max", "min", "first"]
  def validate_aggregation(:aggregation, aggregation) do
    if aggregation in @valid_default_aggregation do
      []
    else
      [
        aggregation:
          "The aggregation #{aggregation} is not a valid aggregation. Valid aggregations are #{Enum.join(@valid_default_aggregation, ", ")}"
      ]
    end
  end

  def validate_min_interval(:min_interval, min_interval) do
    if Sanbase.DateTimeUtils.valid_compound_duration?(min_interval) do
      []
    else
      [
        min_interval:
          "The provided min_interval #{min_interval} is not a valid duration - a number followed by one of: s (second), m (minute), h (hour) or d (day)"
      ]
    end
  end

  def validate_data_type(:data_type, data_type) do
    if data_type in ["timeseries", "histogram"] do
      []
    else
      [
        data_type:
          "Invalid data type #{data_type} is not one of the supported: timeseries or histogram"
      ]
    end
  end
end
