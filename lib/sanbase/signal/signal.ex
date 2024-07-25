defmodule Sanbase.Signal do
  @moduledoc """
  Dispatch module used for fetching signals.

  As there is a single signal adapter now, the dispatching is done directly.
  After a second signals source is introduced, a dispatching logic similar
  to the one found in Sanbase.Metric should be implemented.
  """

  alias Sanbase.Signal.SignalAdapter
  alias Sanbase.Signal.Behaviour, as: Type

  @type datetime :: DateTime.t()
  @type signal :: Type.signal()
  @type signals :: :all | list(signal)
  @type aggregation :: Type.aggregation()
  @type interval :: Type.interval()
  @type selector :: Type.selector()
  @type raw_signals_selector :: :all | selector()
  @type opts :: Keyword.t()

  @spec has_signal?(signal) :: true | {:error, String.t()}
  def has_signal?(signal), do: SignalAdapter.has_signal?(signal)

  @doc ~s"""
  Get available aggregations
  """
  @spec available_aggregations() :: list(aggregation)
  def available_aggregations(), do: SignalAdapter.available_aggregations()

  @doc ~s"""
  Get the human readable name representation of a given signal
  """
  @spec human_readable_name(signal) :: {:ok, String.t()}
  def human_readable_name(signal), do: {:ok, SignalAdapter.human_readable_name(signal)}

  @doc ~s"""
  Get a list of the free signals
  """
  @spec free_signals() :: list(signal)
  def free_signals(), do: SignalAdapter.free_signals()

  @doc ~s"""
  Get a list of the free signals
  """
  @spec restricted_signals() :: list(signal)
  def restricted_signals(), do: SignalAdapter.restricted_signals()

  @doc ~s"""
  Get a map where the key is a signal and the value is its access restriction
  """
  @spec access_map() :: map()
  def access_map(), do: SignalAdapter.access_map()

  @doc ~s"""
  Checks if historical data is allowed for a given `signal`
  """
  @spec historical_data_freely_available?(signal) :: boolean
  def historical_data_freely_available?(signal) do
    get_in(access_map(), [signal, "historical"]) === :free
  end

  @doc ~s"""
  Checks if realtime data is allowed for a given `signal`
  """
  @spec realtime_data_freely_available?(signal) :: boolean
  def realtime_data_freely_available?(signal) do
    get_in(access_map(), [signal, "realtime"]) === :free
  end

  @doc ~s"""
  Get a map where the key is a signal and the value is the min plan it is
  accessible in.
  """
  @spec min_plan_map() :: map()
  def min_plan_map() do
    SignalAdapter.min_plan_map()
  end

  @doc ~s"""
  Get all available signals in the json files
  """
  @spec available_signals() :: list(signal)
  def available_signals() do
    SignalAdapter.available_signals()
  end

  @doc ~s"""
  Get all available signals for a given slug selector
  """
  @spec available_signals(map()) :: Type.available_signals_result()
  def available_signals(selector) do
    SignalAdapter.available_signals(selector)
  end

  @doc ~s"""
  Get available signals with timeseries data types
  """
  @spec available_timeseries_signals() :: list(signal)
  def available_timeseries_signals() do
    SignalAdapter.available_timeseries_signals()
  end

  @doc ~s"""
  Get all available slugs for a given signal
  """
  @spec available_slugs(signal()) :: Type.available_slugs_result()
  def available_slugs(signal) do
    SignalAdapter.available_slugs(signal)
  end

  @doc ~s"""
  Get metadata for a given signal
  """
  @spec metadata(signal) :: {:ok, Type.metadata()} | {:error, String.t()}
  def metadata(signal) do
    case SignalAdapter.has_signal?(signal) do
      true -> SignalAdapter.metadata(signal)
      {:error, error} -> {:error, error}
    end
  end

  @doc ~s"""
  Get the first datetime for which a given signal is available for a given slug
  """
  @spec first_datetime(signal, map) :: Type.first_datetime_result()
  def first_datetime(signal, selector) do
    SignalAdapter.first_datetime(signal, selector)
  end

  @doc ~s"""
  Return all or a subset of the raw signals for all assets.

  Raw signal means that no aggregation is applied and the values and the metadata
  for every signal are returned without combining them with the data of other signals.

  If the `signals` argument has the atom value :all, then all available signals
  that occured in the given from-to interval are returned.

  If the `signals` arguments has a list of signals as a value, then all of those
  signals that occured in the given from-to interval are returned.
  """
  @spec raw_data(signals, raw_signals_selector, datetime, datetime) :: Type.raw_data_result()
  def raw_data(signals, selector, from, to) do
    SignalAdapter.raw_data(signals, selector, from, to)
  end

  @doc ~s"""
  Returns timeseries data (pairs of datetime and float value) for a given set
  of arguments.

  Get a given signal for an interval and time range. The signal's aggregation
  function can be changed by providing the :aggregation key in the last argument.
  If no aggregation is provided, a default one will be used (currently COUNT).
  """
  @spec timeseries_data(signal, selector, datetime, datetime, interval, opts) ::
          Type.timeseries_data_result()
  def timeseries_data(signal, selector, from, to, interval, opts) do
    SignalAdapter.timeseries_data(signal, selector, from, to, interval, opts)
  end

  @doc ~s"""
  Get the aggregated value for a signal, an selector and time range.
  The signal's aggregation function can be changed by the last optional parameter.
  If no aggregation is provided, a default one will be used (currently COUNT).
  """
  @spec aggregated_timeseries_data(signal, selector, datetime, datetime, opts) ::
          Type.aggregated_timeseries_data_result()
  def aggregated_timeseries_data(signal, selector, from, to, opts) do
    SignalAdapter.aggregated_timeseries_data(signal, selector, from, to, opts)
  end
end
