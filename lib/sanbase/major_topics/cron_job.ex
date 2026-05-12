defmodule Sanbase.MajorTopics.CronJob do
  @moduledoc """
  Daily 05:00 UTC job that fetches the latest major-topics batch from ClickHouse
  and stores it in Postgres. Registered in `config/scheduler_config.exs` under
  `Sanbase.Scrapers.Scheduler`.
  """

  require Logger

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.ClickhouseFetcher

  @spec run() :: :ok | {:error, term()}
  def run do
    Logger.info("[MajorTopics.CronJob] Starting fetch")

    with {:ok, payload} <- ClickhouseFetcher.fetch_latest_batch(),
         {:ok, batch} <- MajorTopics.upsert_batch_from_payload(payload) do
      Logger.info(
        "[MajorTopics.CronJob] Stored batch id=#{batch.id} interval=#{batch.interval_text} state=#{batch.state}"
      )

      :ok
    else
      {:error, reason} = err ->
        Logger.error("[MajorTopics.CronJob] Failed: #{inspect(reason)}")
        err
    end
  end
end
