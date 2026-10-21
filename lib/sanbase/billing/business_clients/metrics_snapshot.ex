defmodule Sanbase.Billing.BusinessClients.MetricsSnapshot do
  @moduledoc ~s"""
  The page's headline numbers - churn, renewal, client and at-risk counts - as they
  were on the first day of a month, together with the settings that produced them.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "business_metrics_snapshots" do
    field(:month, :date)
    field(:data, :map, default: %{})

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:month, :data])
    |> validate_required([:month, :data])
    |> unique_constraint(:month)
  end
end
