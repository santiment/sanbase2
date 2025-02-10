defmodule Sanbase.Repo.Migrations.AddPopularSearchTermsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table("popular_search_terms") do
      add(:search_term, :string, null: false)
      add(:selector_type, :string, null: false, default: "text")
      add(:datetime, :datetime)
    end
  end
end
