defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.BalanceDataloader
  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.EcosystemDataloader
  alias SanbaseWeb.Graphql.LabelsDataloader
  alias SanbaseWeb.Graphql.MetricshubDataloader
  alias SanbaseWeb.Graphql.PostgresDataloader
  alias SanbaseWeb.Graphql.PriceDataloader

  @doc """
  Builds the `Dataloader.KV` source for the Absinthe schema, closing
  over the per-request `request_context` so every batch this source runs
  carries it (for `activity_traces_hidden` masking). `nil` outside a
  request scope. See `make_kv_fun/1` for how the context crosses the
  `Dataloader.KV` task boundary.
  """
  @spec data(Sanbase.RequestContext.t() | nil) :: Dataloader.KV.t()
  def data(request_context \\ nil) do
    # Must live on the source — Dataloader ignores `Dataloader.new(timeout:)`.
    # Outlasts the 85s CH budget these batches run. Note it is *per batch*:
    # `Task.async_stream` runs them in waves. See docs/timeouts.md.
    Dataloader.KV.new(make_kv_fun(request_context), timeout: :timer.seconds(105))
  end

  # `Dataloader.KV` runs each batch in a fresh `Task`. Its callback is
  # fixed to `(batch_key, args) -> result`, so we cannot pass ctx as a
  # third arg through the library — instead we close over it. Inside the
  # spawned task we (a) re-seed `Logger.metadata` once as the explicit
  # process-boundary hop (transitional, for callers that still read ctx
  # via `RequestContext.current/0`) and (b) thread ctx into our own
  # `query/3` so downstream code can take it as an explicit argument.
  defp make_kv_fun(nil) do
    fn batch_key, args ->
      query(batch_key, args, nil) |> to_total_result_map(args)
    end
  end

  defp make_kv_fun(%Sanbase.RequestContext{} = ctx) do
    fn batch_key, args ->
      Sanbase.RequestContext.put_logger_metadata(ctx)
      query(batch_key, args, ctx) |> to_total_result_map(args)
    end
  end

  # Under `get_policy: :tuples`, an id missing from the batch result map is
  # returned as `{:error, "Unable to find id ..."}` instead of the `nil` the
  # resolvers expect for "no data". Make every batch result total by filling
  # the missing ids with nil, preserving the old nil semantics.
  #
  # A whole-batch `{:error, reason}` (or any non-map result) is converted to a
  # per-id error map — `Dataloader.KV` would otherwise crash with BadMapError.
  # The per-id `{:error, reason}` values are returned to the resolvers as-is.
  #
  # Some sources key their result map by something else than the loaded ids
  # (e.g. `:eth_spent` loads `%{project:, days:}` but keys by `days`). The
  # extra nil entries added for their loaded ids are never fetched - harmless.
  defp to_total_result_map(result, ids) do
    case result do
      map when is_map(map) and not is_struct(map) ->
        Enum.reduce(ids, map, fn id, acc -> Map.put_new(acc, id, nil) end)

      {:error, reason} ->
        Map.new(ids, fn id -> {id, {:error, reason}} end)

      other ->
        reason = "Unexpected dataloader batch result: #{inspect(other, limit: 5)}"
        Map.new(ids, fn id -> {id, {:error, reason}} end)
    end
  end

  @metricshub_dataloader [
    :social_documents_by_ids
  ]
  @labels_dataloader [
    :address_labels
  ]

  @clickhouse_dataloader [
    :average_daily_active_addresses,
    :average_dev_activity,
    :eth_spent,
    :aggregated_metric,
    :project_info,
    :available_metric_versions
  ]

  @balance_dataloader [
    :address_selector_current_balance,
    :address_selector_balance_change,
    :eth_balance
  ]

  @price_dataloader [
    :volume_change_24h,
    :last_price_usd
  ]

  @postgres_comments_dataloader [
    # comment entity id
    :comment_blockchain_address_id,
    :comment_chart_configuration_id,
    :comment_dashboard_id,
    :comment_insight_id,
    :comment_short_url_id,
    :comment_watchlist_id,
    # Comments count
    :blockchain_addresses_comments_count,
    :chart_configuration_comments_count,
    :dashboard_comments_count,
    :insights_comments_count,
    :short_urls_comments_count,
    :watchlist_comments_count,
    # Votes
    :chart_configuration_vote_stats,
    :chart_configuration_voted_at,
    :dashboard_vote_stats,
    :dashboard_voted_at,
    :query_vote_stats,
    :query_voted_at,
    :insight_vote_stats,
    :insight_voted_at,
    :user_trigger_vote_stats,
    :user_trigger_voted_at,
    :watchlist_vote_stats,
    :watchlist_voted_at
  ]

  @postgres_dataloader [
    :contract_addresses,
    :current_user_address_details,
    :eth_addresses,
    :infrastructure,
    :insights_count_per_user,
    :market_segments,
    :post_categories,
    :project_by_slug,
    :social_volume_query,
    :source_slug_mappings,
    :traded_on_exchanges_count,
    :traded_on_exchanges,
    # Users
    :users_by_id,
    # Founders
    :available_founders_per_slug
    # Trending Words
  ]

  @postgres_dataloader @postgres_dataloader ++ @postgres_comments_dataloader

  @ecosystem_dataloader [:ecosystem_aggregated_metric_data, :ecosystem_timeseries_metric_data]

  @postgres_dataloader MapSet.new(@postgres_dataloader)
  @clickhouse_dataloader MapSet.new(@clickhouse_dataloader)

  def query(queryable, args, request_context) do
    cond do
      queryable in @clickhouse_dataloader ->
        ClickhouseDataloader.query(queryable, args, request_context)

      queryable in @postgres_dataloader ->
        PostgresDataloader.query(queryable, args)

      queryable in @balance_dataloader ->
        BalanceDataloader.query(queryable, args, request_context)

      queryable in @price_dataloader ->
        PriceDataloader.query(queryable, args, request_context)

      queryable in @metricshub_dataloader ->
        MetricshubDataloader.query(queryable, args, request_context)

      queryable in @ecosystem_dataloader ->
        EcosystemDataloader.query(queryable, args, request_context)

      queryable in @labels_dataloader ->
        LabelsDataloader.query(queryable, args, request_context)

      true ->
        raise(RuntimeError, "Unknown queryable provided to the dataloder: #{inspect(queryable)}")
    end
  end
end
