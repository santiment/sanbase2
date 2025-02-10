defmodule Sanbase.Repo.Migrations.FillTagsFromProjects do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Insight.Tag
  alias Sanbase.Project
  alias Sanbase.Repo

  @crypto_market_tag "Crypto Market"

  def up do
    Repo.insert!(%Tag{name: @crypto_market_tag})
    query = from(p in Project, where: not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    projects = Repo.all(query)

    for project <- projects do
      Repo.insert(%Tag{name: project.ticker}, on_conflict: :nothing)
    end
  end

  def down do
    Repo.delete_all(Tag)
  end
end
