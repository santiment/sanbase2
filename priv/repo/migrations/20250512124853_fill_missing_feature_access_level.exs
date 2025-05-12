defmodule Sanbase.Repo.Migrations.FillMissingFeatureAccessLevel do
  use Ecto.Migration
  import Ecto.Query

  def change do
    query = from(u in Sanbase.Accounts.User, where: is_nil(u.feature_access_level))

    Sanbase.Repo.update_all(query, set: [feature_access_level: "released"])
  end
end
