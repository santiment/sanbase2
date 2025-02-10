defmodule Sanbase.Repo.Migrations.RenameCmcSourceToCoinmarketcap do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project.SourceSlugMapping

  def up do
    setup()

    Sanbase.Repo.update_all(
      from(ssm in SourceSlugMapping, where: ssm.source == "cmc", update: [set: [source: "coinmarketcap"]]),
      []
    )
  end

  def down, do: :ok

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
