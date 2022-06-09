defmodule Sanbase.Repo.Migrations.FillContractAddressesTable do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Model.Project

  def up do
    setup()

    project_id_contract_list =
      from(p in Project,
        where: not is_nil(p.main_contract_address),
        select: {p.id, p.main_contract_address, p.token_decimals}
      )
      |> Sanbase.Repo.all()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    insert_data =
      Enum.map(project_id_contract_list, fn {id, address, decimals} ->
        %{
          project_id: id,
          label: "main",
          address: address,
          decimals: decimals,
          inserted_at: now,
          updated_at: now
        }
      end)

    Sanbase.Repo.insert_all(Project.ContractAddress, insert_data)
  end

  def down do
    :ok
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end
