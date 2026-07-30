defmodule SanbaseWeb.Graphql.Resolvers.SignalResolver do
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Sanbase.Project.Selector, only: [args_to_selector: 1]

  alias Sanbase.Signal
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Billing.Plan.Restrictions

  def project(%{slug: slug}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :project_by_slug, slug)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :project_by_slug, slug)}
    end)
  end

  def get_anomalies(_root, %{from: from, to: to} = args, resolution) do
    anomalies = Map.get(args, :anomalies, available_anomalies())

    selector =
      case Map.has_key?(args, :selector) do
        false ->
          :all

        true ->
          {:ok, selector} = args_to_selector(args)
          selector
      end

    Signal.raw_data(anomalies, selector, from, to)
    |> maybe_apply_function(&overwrite_not_accessible_signals(&1, resolution))
    |> maybe_apply_function(&rename_signal_to_anomaly/1)
  end

  defp overwrite_not_accessible_signals(list, resolution) do
    restrictions_map =
      resolution_to_all_signals_restrictions(resolution) |> Map.new(&{&1.name, &1})

    list
    |> Enum.map(fn signal ->
      case should_hide_signal?(signal, restrictions_map) do
        true -> hide_signal_details(signal)
        false -> Map.put(signal, :is_hidden, false)
      end
    end)
  end

  defp available_anomalies() do
    Signal.available_signals()
    |> Enum.filter(&String.starts_with?(&1, "anomaly_"))
  end

  defp rename_signal_to_anomaly(list) do
    Enum.map(list, fn signal ->
      signal
      |> Map.put(:anomaly, signal.signal)
      |> Map.delete(:signal)
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
            DateTime.compare(signal_map.datetime, restricted_from) == :lt

        after_to? =
          match?(%DateTime{}, restricted_to) and
            DateTime.compare(signal_map.datetime, restricted_to) == :gt

        before_from? or after_to?
    end
  end

  defp hide_signal_details(signal) do
    signal
    |> Map.merge(%{
      is_hidden: true,
      datetime: nil,
      value: nil,
      slug: nil,
      metadata: nil
    })
  end

  defp resolution_to_all_signals_restrictions(resolution) do
    %{context: %{requested_product: requested_product, auth: %{plan: plan_name}}} = resolution

    Restrictions.get_all(plan_name, requested_product)
    |> Enum.filter(&(&1.type == "signal"))
  end
end
