defmodule Sanbase.Telegram.UserToken do
  @moduledoc ~s"""
  Module that handles the user_id <-> random token link.
  It is used for deep linking sanbase and telegram accounts.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias __MODULE__
  alias Sanbase.Repo
  alias Sanbase.Auth.User

  @rand_bytes_length 64
  @telegram_authorization_length 18

  @primary_key false
  schema "telegram_user_tokens" do
    field(:token, :string, primary_key: true)
    belongs_to(:user, User, primary_key: true)

    timestamps()
  end

  @doc false
  def changeset(%UserToken{} = user_token, attrs \\ %{}) do
    user_token
    |> cast(attrs, [:user_id, :token])
    |> validate_required([:user_id, :token])
    |> unique_constraint(:token)
    |> unique_constraint(:user_id)
  end

  @doc ~s"""
  Create a new record for a given user_id with a unique token.
  """
  @spec generate(non_neg_integer()) :: {:ok, %UserToken{}} | {:error, Ecto.Changeset.t()}
  def generate(user_id) do
    token = random_string()

    %UserToken{}
    |> changeset(%{user_id: user_id, token: token})
    |> Repo.insert()
  end

  @doc ~s"""
  Delete a record if there is a matching token and user_id pair
  """
  @spec revoke(String.t(), non_neg_integer()) :: {integer(), nil | [term()]}
  def revoke(token, user_id) do
    from(
      ut in UserToken,
      where: ut.token == ^token and ut.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  @doc ~s"""
  Fetch the record containing the given token
  """
  @spec by_token(String.t()) :: %UserToken{} | nil
  def by_token(token) do
    from(ut in UserToken, where: ut.token == ^token)
    |> Repo.one()
  end

  @doc ~s"""
  Fetch the record that refers a given user by their id
  """
  @spec by_user_id(non_neg_integer()) :: %UserToken{} | nil
  def by_user_id(user_id) do
    Repo.get_by(UserToken, user_id: user_id)
  end

  # Private functions

  defp random_string() do
    :crypto.strong_rand_bytes(@rand_bytes_length)
    |> Base.encode32()
    |> binary_part(0, @telegram_authorization_length)
  end
end
