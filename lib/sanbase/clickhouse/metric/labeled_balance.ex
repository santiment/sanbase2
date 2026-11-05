defmodule Sanbase.Clickhouse.MetricAdapter.LabeledBalance do
  @moduledoc ~s"""
  Compute `combined_labeled_balance` as a running sum of `combined_labeled_balance_delta`
  instead of reading the precomputed values.

  Used by `labelled_historical_balance` and the fixed-parameter metrics built on
  `combined_labeled_balance` (`combined_historical_balance_funds`,
  `historical_balance_whales_usd`, etc.).

  The new source is enabled per slug with the `LABELED_BALANCE_FROM_DELTA_SLUGS` env var:
    - `""` - disabled
    - `"bitcoin,litecoin"` - only for these slugs. All requested slugs must be in the list
    - `"*"` - for all slugs

  The `:source` option (`:legacy` or `:delta`) overrides the env var. Used to compare both.

  Labels are not summed. Several labels are supported only when every label belongs to a
  different requested asset (like `santiment/whale_usd_balance(<slug>):v1`).
  """

  import Sanbase.Clickhouse.MetricAdapter.LabeledBalanceSqlQuery
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.Clickhouse.MetricAdapter.Registry
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Utils.Config

  @internal_metric "combined_labeled_balance"
  # The public name of `combined_labeled_balance_delta`
  @delta_metric "labelled_historical_balance_changes"
  @default_version "1.0"
  @per_asset_label_keys ["whale_usd_balance"]
  @max_assets_per_query 1000

  @doc ~s"""
  Return `:delta` if the metric must be computed from the deltas, `:legacy` otherwise.
  """
  def source(metric, selector, opts) do
    with true <- Map.get(Registry.name_to_metric_map(), metric) == @internal_metric,
         %{slug: slug_or_slugs} <- selector,
         true <- (Keyword.get(opts, :version) || @default_version) == @default_version do
      slugs_source(List.wrap(slug_or_slugs), opts)
    else
      _ -> :legacy
    end
  end

  @doc ~s"""
  Same as `source/3`, for code that reads `combined_labeled_balance` directly,
  without a metric (e.g. `Sanbase.Clickhouse.Exchanges`).
  """
  def slugs_source(slugs, opts) do
    case Keyword.get(opts, :source) do
      source when source in [:legacy, :delta] -> source
      nil -> if enabled_for_slugs?(slugs), do: :delta, else: :legacy
    end
  end

  def delta_metric(), do: @delta_metric

  @doc ~s"""
  The metric to use instead of `metric` for the metadata queries (first datetime,
  last computed at, available labels): the delta metric when the balance is computed
  from it, `metric` otherwise.
  """
  def metadata_metric(metric, selector, opts) do
    case source(metric, selector, opts) do
      :delta -> @delta_metric
      :legacy -> metric
    end
  end

  @doc ~s"""
  Return true if the metric is computed from the deltas for all slugs. Used to
  disable the queries that scan all assets (`slugs_by_filter`, `slugs_order`).
  """
  def enabled_for_all_slugs?(metric) do
    Map.get(Registry.name_to_metric_map(), metric) == @internal_metric and
      from_delta_slugs() == "*"
  end

  # One series is returned, so only one asset and one label are supported. The balances
  # of different assets cannot be combined.
  def timeseries_data(metric, %{slug: slug}, from, to, interval, aggregation, filters, opts) do
    with {:ok, ids} <- resolve_ids(metric, List.wrap(slug), filters, opts) do
      case ids.pairs do
        [_, _ | _] ->
          {:error,
           "Several slugs are not supported for #{metric} in timeseriesData, use timeseriesDataPerSlug"}

        _ ->
          timeseries_data_query(ids, from, to, interval, aggregation)
          |> ClickhouseRepo.query_transform(&timeseries_row/1)
          |> maybe_apply_function(&fill_gaps/1)
      end
    end
  end

  def timeseries_data_per_slug(
        metric,
        %{slug: slug},
        from,
        to,
        interval,
        aggregation,
        filters,
        opts
      ) do
    with {:ok, ids} <- resolve_ids(metric, List.wrap(slug), filters, opts) do
      # The rows are ordered by asset and time, so every slug is filled separately
      timeseries_data_per_slug_query(ids, from, to, interval, aggregation)
      |> ClickhouseRepo.query_transform(fn [timestamp, slug, value, has_changed] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          slug: slug,
          value: value,
          has_changed: has_changed
        }
      end)
      |> maybe_apply_function(fn rows ->
        rows
        |> Enum.chunk_by(& &1.slug)
        |> Enum.flat_map(&fill_gaps/1)
        |> Enum.group_by(& &1.datetime, &Map.take(&1, [:slug, :value]))
        |> Enum.map(fn {datetime, data} -> %{datetime: datetime, data: data} end)
        |> Enum.sort_by(& &1.datetime, DateTime)
      end)
    end
  end

  def aggregated_timeseries_data(metric, slugs, from, to, aggregation, filters, opts) do
    with {:ok, ids} <- resolve_ids(metric, slugs, filters, opts) do
      case Enum.chunk_every(ids.pairs, @max_assets_per_query) do
        [_, _ | _] = chunks ->
          aggregated_timeseries_data_in_chunks(ids, chunks, slugs, from, to, aggregation)

        _ ->
          get_aggregated_timeseries_data(ids, slugs, from, to, aggregation)
      end
    end
  end

  @doc ~s"""
  Pair the requested assets with the requested labels.

  `assets` maps slug to asset_id, `labels` maps label fqn to `{label_id, asset_name}`.
  Unknown slugs and labels are dropped, as they have no data.
  """
  def pair_assets_with_labels(metric, slugs, assets, labels) do
    case Map.to_list(labels) do
      [] ->
        {:ok, []}

      [{_fqn, {label_id, _asset_name}}] ->
        {:ok, Enum.map(assets, fn {_slug, asset_id} -> {asset_id, label_id} end)}

      labels_list ->
        pair_per_asset_labels(metric, slugs, assets, labels_list)
    end
  end

  @doc ~s"""
  Fill the intervals without a balance change (`has_changed: 0`) with the last balance.
  The intervals before the first balance are dropped, as there is no balance yet.
  The rows must be ordered by time.
  """
  def fill_gaps(rows) do
    rows
    |> Enum.drop_while(&(&1.has_changed == 0))
    |> Enum.map_reduce(nil, fn
      %{has_changed: 1} = row, _last ->
        row = Map.delete(row, :has_changed)
        {row, row}

      %{has_changed: 0} = row, last ->
        row = row |> Map.delete(:has_changed) |> Map.merge(last_balance(last))
        {row, row}
    end)
    |> elem(0)
  end

  # Private functions

  defp last_balance(%{value_ohlc: %{close: close}}),
    do: %{value_ohlc: %{open: close, high: close, low: close, close: close}}

  defp last_balance(%{value: value}), do: %{value: value}

  defp timeseries_row([timestamp, value, has_changed]) do
    %{datetime: DateTime.from_unix!(timestamp), value: value, has_changed: has_changed}
  end

  defp timeseries_row([timestamp, open, high, low, close, has_changed]) do
    %{
      datetime: DateTime.from_unix!(timestamp),
      value_ohlc: %{open: open, high: high, low: low, close: close},
      has_changed: has_changed
    }
  end

  defp get_aggregated_timeseries_data(ids, slugs, from, to, aggregation) do
    aggregated_timeseries_data_query(ids, slugs, from, to, aggregation)
    |> ClickhouseRepo.query_reduce(%{}, fn [slug, value, has_changed], acc ->
      value = if has_changed == 1, do: value, else: nil
      Map.put(acc, slug, value)
    end)
  end

  # Same as the legacy path: the chunks run in parallel and the failed ones are skipped.
  # The slugs without data are added at the end, as the chunks know only their own slugs.
  defp aggregated_timeseries_data_in_chunks(ids, chunks, slugs, from, to, aggregation) do
    ctx = Sanbase.RequestContext.current()

    result =
      chunks
      |> Sanbase.Parallel.map(
        &get_aggregated_timeseries_data(%{ids | pairs: &1}, [], from, to, aggregation),
        timeout: 55_000,
        max_concurrency: 8,
        ordered: false,
        on_timeout: :kill_task,
        request_context: ctx
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce(Map.new(slugs, &{&1, nil}), &Map.merge(&2, &1))

    {:ok, result}
  end

  # Every label must belong to one of the requested slugs, and every slug can have at
  # most one label. Labels of unknown slugs are dropped.
  defp pair_per_asset_labels(metric, slugs, assets, labels_list) do
    label_slugs = Enum.map(labels_list, fn {_fqn, {_label_id, asset_name}} -> asset_name end)

    if Enum.all?(label_slugs, &(&1 in slugs)) and Enum.uniq(label_slugs) == label_slugs do
      pairs =
        for {_fqn, {label_id, asset_name}} <- labels_list,
            asset_id = Map.get(assets, asset_name),
            not is_nil(asset_id),
            do: {asset_id, label_id}

      {:ok, pairs}
    else
      {:error, "Multiple labels per asset are not supported for #{metric}"}
    end
  end

  defp resolve_ids(metric, slugs, filters, opts) do
    with {:ok, label_fqns} <- label_fqns(metric, slugs, filters, opts),
         {:ok, rows} <- fetch_ids(slugs, label_fqns),
         {:ok, metric_id} <- metric_id(rows),
         {:ok, pairs} <-
           pair_assets_with_labels(metric, slugs, ids_map(rows, "asset"), labels_map(rows)) do
      {:ok, %{metric_id: metric_id, pairs: pairs}}
    end
  end

  defp fetch_ids(slugs, label_fqns) do
    ids_query(slugs, label_fqns, @default_version)
    |> ClickhouseRepo.query_transform(& &1)
  end

  defp metric_id(rows) do
    case ids_map(rows, "metric") |> Map.values() do
      [metric_id] -> {:ok, metric_id}
      _ -> {:error, "Cannot find the metric_id of combined_labeled_balance_delta"}
    end
  end

  defp ids_map(rows, kind) do
    for [^kind, name, id, _] <- rows, into: %{}, do: {name, id}
  end

  defp labels_map(rows) do
    for ["label", fqn, label_id, asset_name] <- rows, into: %{}, do: {fqn, {label_id, asset_name}}
  end

  # The label comes from the selector. For the fixed-parameter metrics without a label in
  # the selector, it is derived from the `label_key` (see MetricAdapter.SqlQuery)
  defp label_fqns(metric, slugs, filters, opts) do
    case {Keyword.get(filters, :label_fqn), opts[:fixed_parameters]} do
      {label_fqn, _} when not is_nil(label_fqn) ->
        {:ok, List.wrap(label_fqn)}

      {nil, %{"labels" => %{"parent_label_key" => _}}} ->
        {:error, "The metric #{metric} requires a 'labelFqn' or 'labelFqns' selector argument"}

      {nil, %{"labels" => %{"label_key" => label_key}}} when label_key in @per_asset_label_keys ->
        {:ok, Enum.map(slugs, &"santiment/#{label_key}(#{&1}):v1")}

      {nil, %{"labels" => %{"label_key" => label_key}}} ->
        {:ok, ["santiment/#{label_key}:v1"]}

      {nil, _} ->
        {:error, "The metric #{metric} requires a 'labelFqn' or 'labelFqns' selector argument"}
    end
  end

  defp enabled_for_slugs?(slugs) do
    case from_delta_slugs() do
      "*" ->
        true

      "" ->
        false

      allowed ->
        allowed = allowed |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
        Enum.all?(slugs, &(&1 in allowed))
    end
  end

  defp from_delta_slugs() do
    (Config.module_get(__MODULE__, :from_delta_slugs, "") || "") |> String.trim()
  end
end
