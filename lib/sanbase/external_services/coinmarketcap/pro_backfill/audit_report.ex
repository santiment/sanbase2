defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.AuditReport do
  alias Sanbase.ExternalServices.Coinmarketcap.ProBackfill

  def run_report(run_id) do
    case ProBackfill.status(run_id) do
      {:error, _} = error ->
        error

      status ->
        summary = %{
          run_id: status.id,
          status: status.status,
          percent_complete: status.percent_complete,
          counts: %{
            total_assets: status.total_assets,
            done_assets: status.done_assets,
            failed_assets: status.failed_assets,
            pending_assets: status.pending_assets
          },
          api_usage: %{
            api_credits_used_total: status.api_credits_used_total,
            api_calls_total: status.api_calls_total,
            rate_limited_calls_total: status.rate_limited_calls_total,
            usage_precision: status.usage_precision
          },
          top_failed_assets: status.top_failed_assets
        }

        {:ok, summary}
    end
  end
end
