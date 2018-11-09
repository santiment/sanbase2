defmodule Sanbase.Influxdb.Measurement do
  @moduledoc ~S"""
    Module, defining the structure and common parts of a influxdb measurement
  """
  defstruct [:timestamp, :fields, :tags, :name]

  alias __MODULE__
  alias Sanbase.ExternalServices.Coinmarketcap.Ticker2, as: Ticker
  alias Sanbase.Model.Project

  @doc ~s"""
    Converts the measurement to a format that the Influxdb and the Instream library
    understand.
    The timestamp should be either a DateTime struct or timestamp in nanoseconds.
  """
  def convert_measurement_for_import(nil), do: nil

  def convert_measurement_for_import(%Measurement{
        timestamp: timestamp,
        fields: fields,
        tags: tags,
        name: name
      })
      when %{} != fields do
    %{
      points: [
        %{
          measurement: name,
          fields: fields,
          tags: tags || [],
          timestamp: timestamp |> format_timestamp()
        }
      ]
    }
  end

  def get_timestamp(%Measurement{timestamp: %DateTime{} = datetime}) do
    DateTime.to_unix(datetime, :nanoseconds)
  end

  def get_timestamp(%Measurement{timestamp: ts}), do: ts

  def get_datetime(%Measurement{timestamp: %DateTime{} = datetime}) do
    datetime
  end

  def get_datetime(%Measurement{timestamp: ts}) do
    DateTime.from_unix!(ts, :nanoseconds)
  end

  def name_from(%Sanbase.Model.Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id})
      when nil != ticker and nil != coinmarketcap_id do
    ticker <> "_" <> coinmarketcap_id
  end

  def name_from(%Ticker{symbol: ticker, id: coinmarketcap_id})
      when nil != ticker and nil != coinmarketcap_id do
    ticker <> "_" <> coinmarketcap_id
  end

  def name_from_slug(slug) when is_nil(slug), do: nil

  def name_from_slug(slug) do
    with ticker when not is_nil(ticker) <- Project.ticker_by_slug(slug) do
      ticker <> "_" <> slug
    else
      _ -> nil
    end
  end

  @doc ~s"""
    convert a list of slugs to measurement-slug map
  """
  def names_from_slugs(slugs) when is_list(slugs) do
    measurement_slug_map =
      Project.tickers_by_slug_list(slugs)
      |> Enum.map(fn {ticker, slug} -> {ticker <> "_" <> slug, slug} end)
      |> Map.new()

    {:ok, measurement_slug_map}
  end

  # Private functions

  defp format_timestamp(%DateTime{} = datetime) do
    DateTime.to_unix(datetime, :nanoseconds)
  end

  defp format_timestamp(ts) when is_integer(ts), do: ts
end
