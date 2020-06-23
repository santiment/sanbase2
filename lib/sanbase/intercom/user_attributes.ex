defmodule Sanbase.Intercom.UserAttributes do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo

  schema "user_intercom_attributes" do
    field(:properties, :map)

    belongs_to(:user, Sanbase.Auth.User)
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_attributes, attrs) do
    user_attributes
    |> cast(attrs, [:user_id, :properties])
    |> validate_required([:user_id, :properties])
  end

  def save(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end
end
