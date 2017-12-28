defmodule Sanbase.Repo.Migrations.ClearProjectsIcoData do
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico

  def change do
    from(p in Project,
    where: like(fragment("lower(?)", p.name), "% (presale)"))
    |> Repo.delete_all

    Repo.delete_all(Ico)
  end
end
