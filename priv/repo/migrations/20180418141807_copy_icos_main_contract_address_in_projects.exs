defmodule Sanbase.Repo.Migrations.CopyIcosMainContractAddressInProjects do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Model.{Ico, Project}
  alias Sanbase.Repo

  def change do
    query =
      from(
        i in Ico,
        where: not is_nil(i.main_contract_address),
        select: [i.project_id, i.main_contract_address],
        order_by: [desc: :id]
      )

    Repo.all(query)
    |> Enum.map(fn [project_id, main_contract_address] ->
      Repo.get!(Project, project_id)
      |> Project.changeset(%{main_contract_address: main_contract_address})
      |> Repo.update!()
    end)
  end
end
