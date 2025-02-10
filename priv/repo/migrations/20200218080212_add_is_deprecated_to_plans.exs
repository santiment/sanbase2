defmodule Sanbase.Repo.Migrations.AddIsDeprecatedToPlans do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add(:is_deprecated, :boolean, default: false)
    end
  end
end
