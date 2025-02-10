defmodule Sanbase.Repo.Migrations.FillContractAddressesTable do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project

  def up do
    setup()

    project_id_contract_list =
      Sanbase.Repo.all(
        from(p in Project,
          where: not is_nil(p.main_contract_address),
          select: {p.id, p.main_contract_address, p.token_decimals}
        )
      )

    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

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

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
