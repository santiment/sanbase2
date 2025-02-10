defmodule Sanbase.Repo.Migrations.AddDataToShortUrl do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:short_urls) do
      add(:data, :string)
    end
  end
end
