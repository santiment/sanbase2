defmodule Sanbase.Dashboard.Query do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dashboard_queries" do
    belongs_to(:user, Sanbase.Accounts.User)
    # belongs_to(:panel, Sanbase.Dashboard.Panel)

    field(:type, :string)
    field(:sql, :map)
    field(:description, :string)
  end
end
