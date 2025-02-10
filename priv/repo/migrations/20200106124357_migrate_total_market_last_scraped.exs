defmodule Sanbase.Repo.Migrations.MigrateTotalMarketLastScraped do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()

    Sanbase.ExternalServices.Coinmarketcap.PriceScrapingProgress.store_progress(
      "TOTAL_MARKET",
      "coinmarketcap",
      ~U[2019-12-11 00:00:00Z]
    )
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
