defmodule Sanbase.Repo.Migrations.CopyIcosMainContractAddressInProjects do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Model.Ico
  alias Sanbase.Project
  alias Sanbase.Repo

  def change do
    query =
      from(
        i in Ico,
        where: not is_nil(i.main_contract_address),
        select: [i.project_id, i.main_contract_address],
        order_by: [desc: :id]
      )

    query
    |> Repo.all()
    |> Enum.map(fn [project_id, main_contract_address] ->
      Project
      |> Repo.get!(project_id)
      |> Project.changeset(%{main_contract_address: main_contract_address})
      |> Repo.update!()
    end)
  end
end
