defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.RunSeederWorker do
  use Oban.Worker,
    queue: :coinmarketcap_pro_backfill_control,
    max_attempts: 10,
    unique: [period: 60 * 60]

  alias Sanbase.ExternalServices.Coinmarketcap.ProBackfill.{Asset, AssetWorker, Run}

  @oban_conf_name :oban_scrapers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    with %Run{} = run <- Run.get(run_id),
         {:ok, run} <- Run.mark_running(run) do
      if run.status == "canceled" do
        :ok
      else
        assets = Asset.list_pending_by_run(run.id)

        jobs =
          Enum.map(assets, fn asset ->
            AssetWorker.new(%{
              run_id: run.id,
              asset_id: asset.id
            })
          end)

        case jobs do
          [] ->
            Run.maybe_mark_completed(run)
            :ok

          _ ->
            Oban.insert_all(@oban_conf_name, jobs)
            :ok
        end
      end
    else
      _ -> :ok
    end
  end
end
