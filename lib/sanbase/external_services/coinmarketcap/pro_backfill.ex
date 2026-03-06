defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill do
  import Ecto.Query

  alias Oban.Job
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Project
  alias Sanbase.Repo

  alias Sanbase.ExternalServices.Coinmarketcap.ProBackfill.{
    Asset,
    Run,
    RunSeederWorker,
    Verification
  }

  @oban_conf_name :oban_scrapers
  @worker_queue :coinmarketcap_pro_backfill_jobs
  @supported_intervals ~w(5m)

  def gap_check(opts), do: Verification.gap_check(opts)

  def start_run(opts) do
    with {:ok, interval} <- fetch_interval(Keyword.get(opts, :interval, "5m")),
         {:ok, result} <- Verification.gap_check(Keyword.put(opts, :interval, interval)) do
      assets_with_gap =
        result.assets
        |> Enum.filter(&(length(&1.fillable_missing_ranges) > 0))

      if assets_with_gap == [] do
        {:ok,
         %{
           status: "no_gap",
           total_assets: result.total_assets,
           fillable_now_assets: result.fillable_now_assets,
           deferred_assets: result.deferred_assets
         }}
      else
        create_run_with_assets(opts, interval, assets_with_gap)
      end
    end
  end

  def pause_run(run_id) do
    with %Run{} = run <- Run.get(run_id),
         {:ok, _} <- Run.mark_paused(run) do
      Oban.pause_queue(@oban_conf_name, queue: @worker_queue)
      :ok
    else
      _ -> {:error, "Run not found"}
    end
  end

  def resume_run(run_id) do
    with %Run{} = run <- Run.get(run_id),
         {:ok, _} <- Run.update_run(run, %{status: "running"}) do
      Oban.resume_queue(@oban_conf_name, queue: @worker_queue)
      :ok
    else
      _ -> {:error, "Run not found"}
    end
  end

  def cancel_run(run_id) do
    with %Run{} = run <- Run.get(run_id),
         {:ok, _} <- Run.mark_canceled(run) do
      from(a in Asset, where: a.run_id == ^run_id and a.status in ["pending", "running"])
      |> Repo.update_all(set: [status: "canceled", finished_at: DateTime.utc_now()])

      :ok
    else
      _ -> {:error, "Run not found"}
    end
  end

  def list_runs(opts \\ []) do
    Run.list(opts)
    |> Enum.map(&run_summary/1)
  end

  def status(run_id) do
    with %Run{} = run <- Run.get(run_id) do
      failed_assets =
        Asset.list_failed_by_run(run_id, 10)
        |> Enum.map(fn a -> %{slug: a.slug, last_error: a.last_error} end)

      %{
        id: run.id,
        status: run.status,
        scope: run.scope,
        interval: run.interval,
        time_start: run.time_start,
        time_end: run.time_end,
        total_assets: run.total_assets,
        done_assets: run.done_assets,
        failed_assets: run.failed_assets,
        pending_assets: run.pending_assets,
        percent_complete: percent_complete(run),
        eta_seconds: eta_seconds(run),
        running_workers: running_workers(run.id),
        top_failed_assets: failed_assets,
        api_credits_used_total: run.api_credits_used_total,
        api_calls_total: run.api_calls_total,
        rate_limited_calls_total: run.rate_limited_calls_total,
        usage_precision: run.usage_precision,
        dry_run: run.dry_run
      }
    else
      _ -> {:error, "Run not found"}
    end
  end

  defp create_run_with_assets(opts, interval, assets_with_gap) do
    now = DateTime.utc_now()

    attrs = %{
      source: "coinmarketcap",
      scope: normalize_scope(opts),
      status: "pending",
      interval: interval,
      time_start: Keyword.fetch!(opts, :time_start),
      time_end: Keyword.fetch!(opts, :time_end),
      dry_run: Keyword.get(opts, :dry_run?, false),
      total_assets: 0,
      pending_assets: 0,
      started_at: nil,
      finished_at: nil
    }

    Repo.transaction(fn ->
      {:ok, run} =
        Run.create(attrs)

      projects_map =
        Project.List.projects_with_source("coinmarketcap",
          include_hidden: true,
          order_by_rank: true
        )
        |> Map.new(&{&1.id, &1})

      rows =
        assets_with_gap
        |> Enum.map(fn gap ->
          project = projects_map[gap.project_id]
          cmc_data = LatestCoinmarketcapData.latest_coinmarketcap_data(project)
          cmc_integer_id = if(cmc_data, do: cmc_data.coinmarketcap_integer_id, else: nil)
          rank = if(cmc_data, do: cmc_data.rank, else: nil)
          ranges = %{"ranges" => gap.fillable_missing_ranges}

          {rank || 9_999_999, -(gap.missing_points_count || 0),
           %{
             run_id: run.id,
             project_id: project.id,
             slug: project.slug,
             cmc_integer_id: cmc_integer_id,
             rank: rank,
             status: "pending",
             missing_ranges: ranges,
             inserted_at: now,
             updated_at: now
           }}
        end)
        |> Enum.sort_by(
          fn {rank, missing_points_count, _row} -> {rank, missing_points_count} end,
          :asc
        )
        |> Enum.map(&elem(&1, 2))
        |> Enum.reject(&is_nil(&1.cmc_integer_id))

      Asset.insert_many(rows)
      Run.update_run(run, %{total_assets: length(rows), pending_assets: length(rows)})

      if rows != [] do
        job = RunSeederWorker.new(%{"run_id" => run.id})
        Oban.insert(@oban_conf_name, job)
      else
        Run.update_run(run, %{status: "completed", finished_at: DateTime.utc_now()})
      end

      run
    end)
  end

  defp normalize_scope(opts) do
    case Keyword.get(opts, :scope) do
      scope when scope in [:single, :all, :list] -> Atom.to_string(scope)
      scope when scope in ["single", "all", "list"] -> scope
      _ -> "all"
    end
  end

  defp fetch_interval(interval) when interval in @supported_intervals, do: {:ok, interval}
  defp fetch_interval(_), do: {:error, "Only 5m interval is currently supported"}

  defp percent_complete(%Run{total_assets: 0}), do: 100.0

  defp percent_complete(%Run{} = run) do
    ((run.done_assets + run.failed_assets) / run.total_assets * 100) |> Float.round(2)
  end

  defp eta_seconds(%Run{started_at: nil}), do: nil
  defp eta_seconds(%Run{done_assets: 0}), do: nil

  defp eta_seconds(%Run{} = run) do
    elapsed = DateTime.diff(DateTime.utc_now(), run.started_at, :second)
    avg_per_asset = elapsed / run.done_assets
    round(avg_per_asset * run.pending_assets)
  end

  defp run_summary(%Run{} = run) do
    %{
      id: run.id,
      status: run.status,
      scope: run.scope,
      interval: run.interval,
      time_start: run.time_start,
      time_end: run.time_end,
      total_assets: run.total_assets,
      done_assets: run.done_assets,
      failed_assets: run.failed_assets,
      pending_assets: run.pending_assets,
      percent_complete: percent_complete(run),
      api_credits_used_total: run.api_credits_used_total,
      api_calls_total: run.api_calls_total,
      rate_limited_calls_total: run.rate_limited_calls_total,
      usage_precision: run.usage_precision
    }
  end

  defp running_workers(run_id) do
    from(j in Job,
      where:
        j.queue == ^to_string(@worker_queue) and j.state == "executing" and
          fragment("?->>'run_id' = ?", j.args, ^to_string(run_id)),
      select: count()
    )
    |> Repo.one()
  end
end
