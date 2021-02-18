defmodule SanbaseWeb.Graphql.Resolvers.SignalResolver do
  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval
  import Sanbase.Metric.Selector, only: [args_to_selector: 1, args_to_raw_selector: 1]

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, maybe_handle_graphql_error: 2]

  alias Sanbase.Signal

  require Logger

  @datapoints 300

  def get_signal(_root, %{signal: signal}, _resolution) do
    case Signal.has_signal?(signal) do
      true -> {:ok, %{signal: signal}}
      {:error, error} -> {:error, error}
    end
  end

  def get_available_signals(_root, _args, _resolution), do: {:ok, Signal.available_signals()}

  def get_available_slugs(_root, _args, %{source: %{signal: signal}}),
    do: Signal.available_slugs(signal)

  def get_metadata(_root, _args, %{source: %{signal: signal}}), do: Signal.metadata(signal)

  def available_since(_root, args, %{source: %{signal: signal}}) do
    with {:ok, selector} <- args_to_selector(args),
         {:ok, first_datetime} <- Signal.first_datetime(signal, selector) do
      {:ok, first_datetime}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Available Since",
        %{signal: signal, selector: args_to_raw_selector(args)},
        error
      )
    end)
  end

  def timeseries_data(
        _root,
        %{from: from, to: to, interval: interval} = args,
        %{source: %{signal: signal}}
      ) do
    with {:ok, selector} <- args_to_selector(args),
         {:ok, opts} = selector_args_to_opts(args),
         {:ok, from, to, interval} <-
           calibrate(Signal, signal, selector, from, to, interval, 86_400, @datapoints),
         {:ok, result} <-
           Signal.timeseries_data(signal, selector, from, to, interval, opts) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    else
      {:error, error} ->
        {:error, handle_graphql_error(signal, args_to_raw_selector(args), error)}
    end
  end

  def aggregated_timeseries_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{signal: signal}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    with {:ok, selector} <- args_to_selector(args),
         {:ok, opts} = selector_args_to_opts(args),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Signal, signal, from, to),
         {:ok, result} <- Signal.aggregated_timeseries_data(signal, selector, from, to, opts) do
      {:ok, Map.values(result) |> List.first()}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(signal, args_to_raw_selector(args), error)
    end)
  end
end
