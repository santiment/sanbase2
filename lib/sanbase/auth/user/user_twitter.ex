defmodule Sanbase.Auth.User.Twitter do
  alias Sanbase.Repo
  alias Sanbase.Auth.User

  def find_or_insert_by_twitter_id(twitter_id, username \\ nil) do
    case Repo.get_by(User, twitter_id: twitter_id) do
      nil ->
        %User{
          twitter_id: twitter_id,
          username: username,
          salt: User.generate_salt(),
          first_login: true
        }
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end
end
