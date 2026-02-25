defmodule Sanbase.Cryptocompare.Jobs do
  alias Sanbase.Project
  alias Sanbase.Cryptocompare.Price

  def remove_oban_jobs_unsupported_assets() do
    {:ok, oban_jobs_base_assets} = get_oban_jobs_base_assets(price_queue())

    supported_base_assets =
      Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
      |> Enum.map(&elem(&1, 0))

    unsupported_base_assets = oban_jobs_base_assets -- supported_base_assets

    Enum.map(unsupported_base_assets, fn base_asset ->
      {:ok, _} = delete_not_completed_base_asset_jobs(price_queue(), base_asset)
    end)
  end

  def get_oban_jobs_base_assets(queue) do
    query = """
    SELECT distinct(args->>'base_asset') FROM oban_jobs
    WHERE queue = $1 AND completed_at IS NULL
    """

    {:ok, %{rows: rows}} = Ecto.Adapters.SQL.query(Sanbase.Repo, query, [queue], timeout: 150_000)
    {:ok, List.flatten(rows)}
  end

  # Private functions

  defp delete_not_completed_base_asset_jobs(queue, base_asset) do
    query = """
    DELETE FROM oban_jobs
    WHERE queue = $1 AND args->>'base_asset' = $2 AND completed_at IS NULL;
    """

    {:ok, %{num_rows: num_rows}} =
      Ecto.Adapters.SQL.query(Sanbase.Repo, query, [queue, base_asset], timeout: 150_000)

    {:ok, %{num_rows: num_rows, base_asset: base_asset}}
  end

  defp price_queue(), do: Price.HistoricalScheduler.queue() |> to_string()
end
