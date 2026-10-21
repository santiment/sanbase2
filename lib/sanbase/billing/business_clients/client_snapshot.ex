defmodule Sanbase.Billing.BusinessClients.ClientSnapshot do
  @moduledoc ~s"""
  One business client's numbers as they were on the first day of a month.

  Written once per month and never changed, so the log state and usage of a past month
  stay as they were reported - those two cannot be recomputed later.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "business_client_snapshots" do
    field(:month, :date)
    field(:data, :map, default: %{})

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:month, :user_id, :data])
    |> validate_required([:month, :data])
    |> unique_constraint([:month, :user_id])
  end
end
