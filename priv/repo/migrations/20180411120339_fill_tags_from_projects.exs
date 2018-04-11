defmodule Sanbase.Repo.Migrations.FillTagsFromProjects do
  use Ecto.Migration

  import Ecto.Query

  @crypto_market_tag "Crypto Market"

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Voting.Tag

  def up do
    Repo.insert!(%Tag{name: @crypto_market_tag})
    query = from(p in Project, where: not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    projects = Repo.all(query)

    for project <- projects do
      Repo.insert!(%Tag{name: project.ticker})
    end
  end

  def down do
    Repo.delete_all(Tag)
  end
end
