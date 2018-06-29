defmodule Sanbase.Auth.UserApiKeyToken do
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

  def changeset(%UserApiKeyToken{} = user_api_key_token, attrs \\ %{}) do
    user_api_key_token
    |> cast(attrs, [:token, :user_id])
    |> validate_required([:token, :user_id])
    |> unique_constraint(:token)
  end

  def user_tokens(%User{id: user_id}) do
    user_tokens(user_id)
  end

  def user_tokens(user_id) when is_integer(user_id) do
    query =
      from(
        pair in UserApiKeyToken,
        where: pair.user_id == ^user_id,
        select: pair.token
      )

    {:ok, Sanbase.Repo.all(query)}
  end

  def add_user_token(%User{id: user_id} = user, token) do
    %UserApiKeyToken{}
    |> changeset(%{user_id: user_id, token: token})
    |> Repo.insert()
  end
end
