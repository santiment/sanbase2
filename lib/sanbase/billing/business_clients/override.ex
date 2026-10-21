defmodule Sanbase.Billing.BusinessClients.Override do
  @moduledoc ~s"""
  An admin's decision on whether a user counts as a business client, for the email
  domains the free-provider rule gets wrong. It applies only to the plans that need a
  business email; a business plan always counts.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "business_client_overrides" do
    field(:business, :boolean)
    field(:note, :string)

    belongs_to(:user, Sanbase.Accounts.User)
    belongs_to(:set_by, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:business, :note])
    |> validate_required([:business, :user_id])
    |> unique_constraint(:user_id)
  end
end
