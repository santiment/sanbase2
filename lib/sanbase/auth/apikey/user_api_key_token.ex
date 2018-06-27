defmodule Sanbase.Auth.UserApiKeyToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Auth.User

  schema "user_api_key_tokens" do
    field(:token, :string)

    belongs_to(:user, User)
  end

  def changeset(%UserApiKeyToken{} = user_api_key_token, attrs \\ %{}) do
    user_api_key_token
    |> cast(attrs, [:token, :user_id])
    |> validate_required([:token, :user_id])
    |> unique_constraint(:token)
  end
end
