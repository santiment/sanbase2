defmodule Sanbase.Repo.Migrations.RescrapeBatPrice do
  use Ecto.Migration

  alias Sanbase.Prices.Store

  def up do
    Application.ensure_all_started(:hackney)
    start_store()

    # There is missing/incorrect data for BAT on prod for 24.04.2018. Just in case rescrape from an earlier date
    Store.update_last_history_datetime_cmc(
      "basic-attention-token",
      DateTime.from_naive!(~N[2018-04-15 12:00:00], "Etc/UTC")
    )
  end

  def down, do: :ok

  # Helper functions

  defp start_store() do
    opts = [strategy: :one_for_one, max_restarts: 5, max_seconds: 1]
    Supervisor.start_link([Store.child_spec()], opts)
  end
end
