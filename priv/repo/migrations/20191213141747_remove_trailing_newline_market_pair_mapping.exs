defmodule Sanbase.Repo.Migrations.RemoveTrailingNewlineMarketPairMapping do
  use Ecto.Migration
  alias Sanbase.Exchanges.MarketPairMapping
  alias Sanbase.Repo

  # Remove trailing newline from `to_ticker` column
  def up do
    setup()

    MarketPairMapping
    |> Sanbase.Repo.all()
    |> Enum.map(fn mpm ->
      mpm
      |> MarketPairMapping.changeset(%{to_ticker: String.trim_trailing(mpm.to_ticker)})
      |> Repo.update!()
    end)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
