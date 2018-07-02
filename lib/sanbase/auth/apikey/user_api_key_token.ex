defmodule Sanbase.Auth.UserApikeyToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  schema "user_api_key_tokens" do
    field(:token, :string)

    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%UserApikeyToken{} = user_api_key_token, attrs \\ %{}) do
    user_api_key_token
    |> cast(attrs, [:token, :user_id])
    |> validate_required([:token, :user_id])
    |> unique_constraint(:token)
  end

  def user_tokens(%User{id: user_id}) do
    query =
      from(
        pair in UserApikeyToken,
        where: pair.user_id == ^user_id,
        select: pair.token
      )

    {:ok, Sanbase.Repo.all(query)}
  end

  def add_user_token(%User{id: user_id}, token) do
    %UserApikeyToken{}
    |> changeset(%{user_id: user_id, token: token})
    |> Repo.insert()
  end

  def remove_user_token(%User{id: user_id}, token) do
    from(
      pair in UserApikeyToken,
      where: pair.token == ^token and pair.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  def has_token?(token) do
    case Repo.get_by(UserApikeyToken, token: token) do
      nil -> false
      _ -> true
    end
  end

  def user_has_token?(%User{id: user_id}, token) do
    query =
      from(
        pair in UserApikeyToken,
        where: pair.user_id == ^user_id and pair.token == ^token
      )

    case Repo.all(query) do
      [] ->
        false

      _ ->
        true
    end
  end

  def user_by_token(token) do
    case Repo.get_by(UserApikeyToken, token: token) do
      nil ->
        false

      %UserApikeyToken{user_id: user_id} ->
        User.by_id(user_id)
    end
  end
end
