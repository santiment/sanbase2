defmodule SanbaseWeb.ExAdmin.Model.Infrastructure do
  use ExAdmin.Register

  alias Sanbase.Project

  register_resource Sanbase.Model.Infrastructure do
    show infr do
      attributes_table(all: true)

      panel "Projects with this Infrastructure" do
        table_for projects_with_infrastructure(infr) do
          column(:name, link: true)
          column(:ticker)
          column(:slug)
        end
      end
    end
  end

  def projects_with_infrastructure(infr) do
    from(
      p in Project,
      where: p.infrastructure_id == ^infr.id,
      preload: [:infrastructure]
    )
    |> Sanbase.Repo.all()
  end
end
