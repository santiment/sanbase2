defmodule :"Elixir.Sanbase.Repo.Migrations.Fix-project-logos" do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  def up do
    [
      {"Civic", "civic.png"},
      {"Status", "status.png"},
      {"Iconomi", "iconomi.png"},
      {"DigixDAO", "digixdao.png"},
      {"Aeternity", "aeternity.png"},
      {"Basic Attention Token", "basic-attention-token.png"},
      {"Golem", "golem.png"},
      {"TenX", "tenx.png"},
      {"Populous", "populous.png"},
      {"MobileGo", "mobilego.png"},
      {"Aragon", "aragon.png"},
      {"SingularDTV", "singulardtv.png"},
      {"Gnosis", "gnosis.png"},
      {"Bancor", "bancor.png"},
      {"EOS", "eos.png"}
    ]
    |> Enum.each(fn {name, logo_url} = project ->
      Project
      |> where([p], p.name == ^name)
      |> Repo.update_all(set: [logo_url: logo_url])
    end)
  end

  def down do
  end
end
