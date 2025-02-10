defmodule Sanbase.Webinars.Registration do
  @moduledoc """
  Mapping between users and webinars
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.Webinar

  schema "webinar_registrations" do
    belongs_to(:user, User)
    belongs_to(:webinar, Webinar)

    timestamps()
  end

  @doc false
  def changeset(registration, attrs) do
    registration
    |> cast(attrs, [:user_id, :webinar_id])
    |> validate_required([:user_id, :webinar_id])
    |> unique_constraint(:user_webinar, name: :webinar_registrations_user_id_webinar_id_index)
  end

  def create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert(on_conflict: :nothing)
  end

  def list_users_in_webinar(webinar_id) do
    from(wr in __MODULE__, where: wr.webinar_id == ^webinar_id, preload: [:user])
    |> Repo.all()
    |> Enum.map(& &1.user)
  end

  def list_webinars_for_users(user_id) do
    from(wr in __MODULE__, where: wr.user_id == ^user_id, preload: [:webinar])
    |> Repo.all()
    |> Enum.map(& &1.webinar)
  end
end
