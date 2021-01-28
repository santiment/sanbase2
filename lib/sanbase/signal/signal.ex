defmodule Sanbase.Signal do
  alias Sanbase.Signal.SignalAdapter

  def has_signal?(signal), do: SignalAdapter.has_signal?(signal)

  def available_aggregations(), do: SignalAdapter.available_aggregations()

  def available_signals() do
    SignalAdapter.available_signals()
  end

  def available_signals(slug) do
    SignalAdapter.available_signals(slug)
  end

  def available_slugs(signal) do
    SignalAdapter.available_slugs(signal)
  end

  def metadata(signal) do
    SignalAdapter.metadata(signal)
  end

  def first_datetime(signal, slug) do
    SignalAdapter.first_datetime(signal, slug)
  end

  def timeseries_data(signal, slug, from, to, interval, aggregation) do
    SignalAdapter.timeseries_data(signal, slug, from, to, interval, aggregation)
  end

  def aggregated_timeseries_data(signal, slug_or_slugs, from, to, aggregation) do
    SignalAdapter.aggregated_timeseries_data(signal, slug_or_slugs, from, to, aggregation)
  end
end
