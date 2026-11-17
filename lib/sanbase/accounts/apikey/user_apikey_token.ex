defmodule Sanbase.Accounts.UserApikeyToken do
  @moduledoc ~s"""
  The tokens backing users' API keys.

  Revoking a key sets `revoked_at` and keeps the row, so there is a record of
  which keys existed and when they were revoked. A revoked token no longer
  resolves to a user and does not count towards the per-user limit.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @api_keys_per_user_limit 10
  def api_keys_per_user_limit(), do: @api_keys_per_user_limit

  schema "user_api_key_tokens" do
    field(:token, :string)
    field(:revoked_at, :utc_datetime)

    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%UserApikeyToken{} = user_api_key_token, attrs \\ %{}) do
    user_api_key_token
    |> cast(attrs, [:token, :user_id])
    |> validate_required([:token, :user_id])
    |> unique_constraint(:token)
  end

  def user_can_generate_apikey?(%User{id: user_id}) do
    query =
      from(
        pair in UserApikeyToken,
        where: pair.user_id == ^user_id and is_nil(pair.revoked_at),
        select: count(pair.id)
      )

    case Sanbase.Repo.one(query) do
      num when is_number(num) and num < @api_keys_per_user_limit ->
        true

      _ ->
        {:error, "Cannot create more than #{@api_keys_per_user_limit} API keys"}
    end
  end

  def user_tokens(%User{id: user_id}) do
    query =
      from(
        pair in UserApikeyToken,
        where: pair.user_id == ^user_id and is_nil(pair.revoked_at),
        select: pair.token
      )

    {:ok, Sanbase.Repo.all(query)}
  end

  @doc ~s"""
  All token rows of the user, revoked ones included.
  """
  def user_tokens_structs(%User{id: user_id}) do
    query =
      from(
        pair in UserApikeyToken,
        where: pair.user_id == ^user_id
      )

    {:ok, Sanbase.Repo.all(query)}
  end

  def add_user_token(%User{id: user_id}, token) do
    %UserApikeyToken{}
    |> changeset(%{user_id: user_id, token: token})
    |> Repo.insert()
  end

  @doc ~s"""
  Revoke the user's token. The row is kept with `revoked_at` set.
  """
  def revoke_user_token(%User{id: user_id}, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(
      pair in UserApikeyToken,
      where: pair.token == ^token and pair.user_id == ^user_id and is_nil(pair.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now, updated_at: DateTime.to_naive(now)])
  end

  @doc ~s"""
  Revoke a token row. Revoking an already revoked row keeps its first `revoked_at`.
  """
  def revoke(%UserApikeyToken{revoked_at: nil} = token) do
    token
    |> change(revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def revoke(%UserApikeyToken{} = token), do: {:ok, token}

  @doc ~s"""
  Whether `token` exists and is not revoked.
  """
  def has_token?(token) do
    from(pair in UserApikeyToken, where: pair.token == ^token and is_nil(pair.revoked_at))
    |> Repo.exists?()
  end

  def user_has_token?(%User{id: user_id}, token) do
    query =
      from(
        pair in UserApikeyToken,
        where: pair.user_id == ^user_id and pair.token == ^token and is_nil(pair.revoked_at)
      )

    case Repo.all(query) do
      [] ->
        false

      _ ->
        true
    end
  end
end
