defmodule SanbaseWeb.Graphql.Resolvers.SignalResolver do
  @moduledoc false
  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Sanbase.Project.Selector, only: [args_to_selector: 1, args_to_raw_selector: 1]

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, maybe_handle_graphql_error: 2]

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval
  import SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.Billing.Plan.Restrictions
  alias Sanbase.Signal
  alias SanbaseWeb.Graphql.SanbaseDataloader

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

  def get_raw_signals(_root, %{from: from, to: to} = args, resolution) do
    signals = Map.get(args, :signals, :all)

    selector =
      if Map.has_key?(args, :selector) do
        {:ok, selector} = args_to_selector(args)
        selector
      else
        :all
      end

    signals
    |> Signal.raw_data(selector, from, to)
    |> maybe_apply_function(&overwrite_not_accessible_signals(&1, resolution))
  end

  def get_available_signals(_root, _args, _resolution), do: {:ok, Signal.available_signals()}

  def get_available_slugs(_root, _args, %{source: %{signal: signal}}), do: Signal.available_slugs(signal)

  def get_metadata(_root, _args, resolution) do
    %{source: %{signal: signal}} = resolution

    case Signal.metadata(signal) do
      {:ok, metadata} ->
        restrictions = resolution_to_signal_restrictions(resolution)
        {:ok, Map.merge(restrictions, metadata)}

      {:error, error} ->
        {:error, handle_graphql_error("metadata", %{signal: signal}, error)}
    end
  end

  def available_since(_root, args, %{source: %{signal: signal}}) do
    with_result =
      with {:ok, selector} <- args_to_selector(args) do
        Signal.first_datetime(signal, selector)
      end

    maybe_handle_graphql_error(with_result, fn error ->
      handle_graphql_error(
        "Available Since",
        %{signal: signal, selector: args_to_raw_selector(args)},
        error
      )
    end)
  end

  def timeseries_data(_root, %{from: from, to: to, interval: interval} = args, %{source: %{signal: signal}}) do
    with {:ok, selector} <- args_to_selector(args),
         {:ok, opts} = selector_args_to_opts(args),
         {:ok, from, to, interval} <-
           calibrate(Signal, signal, selector, from, to, interval, 86_400, @datapoints),
         {:ok, result} <- Signal.timeseries_data(signal, selector, from, to, interval, opts) do
      {:ok, Enum.reject(result, &is_nil/1)}
    else
      {:error, error} ->
        {:error, handle_graphql_error(signal, args_to_raw_selector(args), error)}
    end
  end

  def aggregated_timeseries_data(_root, %{from: from, to: to} = args, %{source: %{signal: signal}}) do
    with_result =
      with {:ok, selector} <- args_to_selector(args),
           {:ok, opts} = selector_args_to_opts(args),
           {:ok, result} <- Signal.aggregated_timeseries_data(signal, selector, from, to, opts) do
        {:ok, result |> Map.values() |> List.first()}
      end

    maybe_handle_graphql_error(with_result, fn error ->
      handle_graphql_error(signal, args_to_raw_selector(args), error)
    end)
  end

  defp overwrite_not_accessible_signals(list, resolution) do
    restrictions_map =
      resolution |> resolution_to_all_signals_restrictions() |> Map.new(&{&1.name, &1})

    Enum.map(list, fn signal ->
      if should_hide_signal?(signal, restrictions_map) do
        hide_signal_details(signal)
      else
        Map.put(signal, :is_hidden, false)
      end
    end)
  end

  defp should_hide_signal?(signal_map, restrictions_map) do
    case Map.get(restrictions_map, signal_map.signal) do
      %{is_accessible: false} ->
        true

      %{is_accessible: true, is_restricted: false} ->
        false

      %{restricted_from: restricted_from, restricted_to: restricted_to} ->
        before_from? =
          match?(%DateTime{}, restricted_from) and
            DateTime.before?(signal_map.datetime, restricted_from)

        after_to? =
          match?(%DateTime{}, restricted_to) and
            DateTime.after?(signal_map.datetime, restricted_to)

        before_from? or after_to?
    end
  end

  defp hide_signal_details(signal) do
    Map.merge(signal, %{is_hidden: true, datetime: nil, value: nil, slug: nil, metadata: nil})
  end

  defp resolution_to_signal_restrictions(resolution) do
    %{context: %{requested_product: requested_product, auth: %{plan: plan_name}}} = resolution
    %{source: %{signal: signal}} = resolution

    Restrictions.get({:signal, signal}, requested_product, requested_product, plan_name)
  end

  defp resolution_to_all_signals_restrictions(resolution) do
    %{context: %{requested_product: requested_product, auth: %{plan: plan_name}}} = resolution

    plan_name
    |> Restrictions.get_all(requested_product)
    |> Enum.filter(&(&1.type == "signal"))
  end
end
