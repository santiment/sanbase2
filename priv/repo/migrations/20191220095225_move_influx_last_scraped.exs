defmodule Sanbase.Repo.Migrations.MoveInfluxLastScraped do
  use Ecto.Migration

  def change do
    setup()
    start_influxdb_store()

    get_last_scraped_datetimes()
    |> store_last_scraped_datetiems()
  end

  # Returns list of {slug, datetime} tuples
  defp get_last_scraped_datetimes() do
    Sanbase.Prices.Store.all_last_history_datetimes_cmc()
  end

  defp store_last_scraped_datetiems(data) do
    now = Timex.now()

    data =
      Enum.map(data, fn
        {slug, %DateTime{} = datetime} ->
          %{
            identifier: slug,
            datetime: datetime,
            source: "coinmarketcap",
            inserted_at: now,
            updated_at: now
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    Sanbase.Repo.insert_all(Sanbase.ExternalServices.Coinmarketcap.PriceScrapingProgress, data,
      on_conflict: :nothing
    )
  end

  defp start_influxdb_store() do
    opts = [strategy: :one_for_one, max_restarts: 5, max_seconds: 1]
    Supervisor.start_link([Sanbase.Prices.Store.child_spec()], opts)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
