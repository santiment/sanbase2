defmodule Sanbase.Accounts.User.Twitter do
  @moduledoc false
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  def find_or_insert_by_twitter_id(twitter_id, attrs \\ %{}) do
    case Repo.get_by(User, twitter_id: twitter_id) do
      nil ->
        user_create_attrs =
          Map.merge(
            attrs,
            %{twitter_id: twitter_id, salt: User.generate_salt(), first_login: true}
          )

        %User{}
        |> User.changeset(user_create_attrs)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def update_twitter_id(%User{twitter_id: twitter_id} = user, twitter_id), do: {:ok, user}

  def update_twitter_id(%User{} = user, twitter_id) do
    user
    |> User.changeset(%{twitter_id: twitter_id})
    |> Sanbase.Repo.update()
  end
end
