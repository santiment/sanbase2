defmodule Sanbase.Repo.Migrations.SetProjectsDefaults do
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Model.Infrastructure

  def change do
    infrastructure = Infrastructure.get_or_insert("ETH");

    from(p in Project, where: is_nil(p.infrastructure_id))
    |> Repo.update_all(set: [infrastructure_id: infrastructure.id])
  end
end
