defmodule Sanbase.Influxdb.Measurement do
  @moduledoc ~S"""
    Module, defining the structure and common parts of a influxdb measurement
  """
  defstruct [:timestamp, :fields, :tags, :name]

  alias __MODULE__

  def convert_measurement_for_import(nil), do: nil

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

  def get_timestamp(%Measurement{timestamp: ts}), do: ts

  def get_datetime(%Measurement{timestamp: ts}) do
    DateTime.from_unix!(ts, :nanoseconds)
  end
end
