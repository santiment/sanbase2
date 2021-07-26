defmodule Sanbase.Repo.Migrations.RescrapeKncPrice do
  use Ecto.Migration

  alias Sanbase.Prices.Store

  def up do
    Application.ensure_all_started(:hackney)
    start_store()

    # The data from CMC was wrong but they fixed it. Setting the last datetime
    # when the data was scraped will trigger rescrapping from that datetime.
    Store.update_last_history_datetime_cmc(
      "kyber-network",
      DateTime.from_naive!(~N[2018-04-04 12:00:00], "Etc/UTC")
    )
  end

  def down, do: :ok

  # Helper functions

  defp start_store() do
    opts = [strategy: :one_for_one, max_restarts: 5, max_seconds: 1]
    Supervisor.start_link([Store.child_spec()], opts)
  end
end
