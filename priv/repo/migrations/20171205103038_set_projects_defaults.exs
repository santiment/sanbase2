defmodule Sanbase.Repo.Migrations.SetProjectsDefaults do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Sanbase.Model.Infrastructure
  alias Sanbase.Project
  alias Sanbase.Repo

  def change do
    infrastructure = Infrastructure.get_or_insert("ETH")

    Repo.update_all(from(p in Project, where: is_nil(p.infrastructure_id)), set: [infrastructure_id: infrastructure.id])
  end
end
