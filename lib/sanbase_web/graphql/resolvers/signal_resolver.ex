defmodule SanbaseWeb.Graphql.Resolvers.SignalResolver do
  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval
  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Sanbase.Model.Project.Selector, only: [args_to_selector: 1, args_to_raw_selector: 1]

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, maybe_handle_graphql_error: 2]

  alias Sanbase.Signal
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Billing.Plan.Restrictions

  require Logger

  @datapoints 300

  def project(%{slug: slug}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :project_by_slug, slug)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :project_by_slug, slug)}
    end)
  end

  def get_signal(_root, %{signal: signal}, _resolution) do
    case Signal.has_signal?(signal) do
      true -> {:ok, %{signal: signal}}
      {:error, error} -> {:error, error}
    end
  end

  def get_raw_signals(_root, %{from: from, to: to} = args, _resolution) do
    signals = Map.get(args, :signals, :all)

    selector =
      case Map.has_key?(args, :selector) do
        false ->
          :all

        true ->
          {:ok, selector} = args_to_selector(args)
          selector
      end

    Signal.raw_data(signals, selector, from, to)
  end

  def get_available_signals(_root, _args, _resolution), do: {:ok, Signal.available_signals()}

  def get_available_slugs(_root, _args, %{source: %{signal: signal}}),
    do: Signal.available_slugs(signal)

  def get_metadata(_root, _args, %{source: %{signal: signal}} = resolution) do
    %{context: %{product_id: product_id, auth: %{plan: plan}}} = resolution

    case Signal.metadata(signal) do
      {:ok, metadata} ->
        access_restrictions = Restrictions.get({:signal, signal}, plan, product_id)
        {:ok, Map.merge(access_restrictions, metadata)}

      {:error, error} ->
        {:error, handle_graphql_error("metadata", %{signal: signal}, error)}
    end
  end

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
    with {:ok, selector} <- args_to_selector(args),
         {:ok, opts} = selector_args_to_opts(args),
         {:ok, result} <- Signal.aggregated_timeseries_data(signal, selector, from, to, opts) do
      {:ok, Map.values(result) |> List.first()}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(signal, args_to_raw_selector(args), error)
    end)
  end
end
