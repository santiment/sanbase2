defmodule Sanbase.Repo.Migrations.RenameCmcSourceToCoinmarketcap do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Model.Project.SourceSlugMapping

  def up do
    setup()

    from(ssm in SourceSlugMapping,
      where: ssm.source == "cmc",
      update: [set: [source: "coinmarketcap"]]
    )
    |> Sanbase.Repo.update_all([])
  end

  def down, do: :ok

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end
