defmodule Sanbase.Repo.Migrations.SetProjectsDefaults do
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Sanbase.Repo
  alias Sanbase.Model
  alias Sanbase.Model.Project

  def change do
    infrastructure = Model.get_or_insert_infrastructure("ETH");

    from(p in Project, where: is_nil(p.infrastructure_id))
    |> Repo.update_all(set: [infrastructure_id: infrastructure.id])
  end
end
