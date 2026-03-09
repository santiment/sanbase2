defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.AssetWorker do
  use Oban.Worker,
    queue: :coinmarketcap_pro_backfill_jobs,
    max_attempts: 20,
    unique: [period: 60 * 60]

  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint

  alias Sanbase.ExternalServices.Coinmarketcap.ProBackfill.{
    Asset,
    ProApiClient,
    Run
  }

  @prices_exporter :prices_exporter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "asset_id" => asset_id}}) do
    with %Run{} = run <- Run.get(run_id),
         %Asset{} = asset <- Asset.get(asset_id) do
      execute(run, asset)
    else
      _ -> :ok
    end
  end

  defp execute(%Run{status: "paused"}, _asset), do: {:snooze, 30}

  defp execute(%Run{status: status}, %Asset{} = asset)
       when status in ["canceled", "completed", "failed"] do
    Asset.mark_canceled(asset)
    :ok
  end

  defp execute(%Run{}, %Asset{status: status})
       when status in ["completed", "failed", "canceled"],
       do: :ok

  defp execute(%Run{} = run, %Asset{} = asset) do
    with {:ok, _asset} <- Asset.mark_running(asset),
         {:ok, result} <- fetch_all_ranges(run, asset),
         {:ok, _} <- maybe_export(run, asset.slug, result.price_points) do
      points_exported = length(result.price_points)

      Asset.mark_completed(asset, %{
        points_exported: points_exported,
        api_credits_used: result.usage.api_credits_used,
        api_calls_total: result.usage.api_calls_total,
        rate_limited_calls_total: result.usage.rate_limited_calls_total,
        usage_precision: result.usage.usage_precision
      })

      Run.increment_stats(run.id, %{
        done_assets: 1,
        pending_assets: -1,
        api_credits_used_total: result.usage.api_credits_used,
        api_calls_total: result.usage.api_calls_total,
        rate_limited_calls_total: result.usage.rate_limited_calls_total,
        usage_precision: result.usage.usage_precision
      })

      Run.get(run.id)
      |> Run.maybe_mark_completed()

      :ok
    else
      {:snooze, seconds, usage} ->
        Run.increment_stats(run.id, %{
          api_calls_total: usage.api_calls_total || 1,
          rate_limited_calls_total: usage.rate_limited_calls_total || 1
        })

        Asset.update_asset(asset, %{
          api_calls_total: asset.api_calls_total + (usage.api_calls_total || 1),
          rate_limited_calls_total:
            asset.rate_limited_calls_total + (usage.rate_limited_calls_total || 1)
        })

        {:snooze, seconds}

      {:error, error} ->
        Asset.mark_failed(asset, error)

        Run.increment_stats(run.id, %{
          failed_assets: 1,
          pending_assets: -1,
          last_error: error
        })

        Run.get(run.id)
        |> Run.maybe_mark_completed()

        {:error, error}
    end
  end

  defp maybe_export(%Run{dry_run: true}, _slug, _price_points), do: {:ok, :dry_run}

  defp maybe_export(%Run{}, slug, price_points) do
    price_points
    |> PricePoint.sanity_filters(slug)
    |> Enum.map(&PricePoint.json_kv_tuple(&1, slug))
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)

    {:ok, :exported}
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp fetch_all_ranges(run, asset) do
    ranges =
      asset.missing_ranges
      |> Map.get("ranges", [])
      |> Enum.map(&normalize_range/1)

    Enum.reduce_while(ranges, {:ok, %{price_points: [], usage: usage_zero()}}, fn range,
                                                                                  {:ok, acc} ->
      case ProApiClient.fetch_range(asset.cmc_integer_id, range.from_unix, range.to_unix,
             interval: run.interval
           ) do
        {:ok, points, usage} ->
          merged = %{
            price_points: acc.price_points ++ points,
            usage: usage_add(acc.usage, usage)
          }

          {:cont, {:ok, merged}}

        {:rate_limited, seconds, usage} ->
          {:halt, {:snooze, seconds, usage}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp normalize_range(%{"from_unix" => from_unix, "to_unix" => to_unix}),
    do: %{from_unix: from_unix, to_unix: to_unix}

  defp normalize_range(%{from_unix: from_unix, to_unix: to_unix}),
    do: %{from_unix: from_unix, to_unix: to_unix}

  defp usage_zero do
    %{
      api_credits_used: 0.0,
      api_calls_total: 0,
      rate_limited_calls_total: 0,
      usage_precision: "exact"
    }
  end

  defp usage_add(left, right) do
    %{
      api_credits_used: (left.api_credits_used || 0.0) + (right[:api_credits_used] || 0.0),
      api_calls_total: (left.api_calls_total || 0) + (right[:api_calls_total] || 0),
      rate_limited_calls_total:
        (left.rate_limited_calls_total || 0) + (right[:rate_limited_calls_total] || 0),
      usage_precision: usage_precision(left.usage_precision, right[:usage_precision] || "exact")
    }
  end

  defp usage_precision("mixed", _), do: "mixed"
  defp usage_precision(_, "mixed"), do: "mixed"
  defp usage_precision(a, a), do: a
  defp usage_precision(_, _), do: "mixed"
end
