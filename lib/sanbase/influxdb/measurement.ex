defmodule Sanbase.Influxdb.Measurement do
  @moduledoc ~S"""
    Module, defining the structure and common parts of a influxdb measurement
  """
  defstruct [:timestamp, :fields, :tags, :name]

  alias Sanbase.Influxdb.Measurement

  def convert_measurement_for_import(%Measurement{
        timestamp: timestamp,
        fields: fields,
        tags: tags,
        name: name
      }) do
    %{
      points: [
        %{
          measurement: name,
          fields: fields,
          tags: tags || [],
          timestamp: timestamp
        }
      ]
    }
  end
end