defmodule Sanbase.Intercom.UserAttributes do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

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

  def get_attributes_for_users(user_ids, from, to) do
    from(ua in __MODULE__,
      where:
        ua.user_id in ^user_ids and
          ua.inserted_at >= ^from and
          ua.inserted_at <= ^to
    )
    |> Repo.all()
    |> Enum.map(fn ua ->
      %{
        user_id: ua.user_id,
        inserted_at: ua.inserted_at,
        attributes: ua.properties
      }
    end)
  end
end
