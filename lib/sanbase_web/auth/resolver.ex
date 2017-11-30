defmodule SanbaseWeb.Auth.Resolver do
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  def current_user(_root, %{context: %{current_user: user}}) do
    {:ok, user}
  end

  def current_user(_root, _args), do: {:ok, nil}

  def eth_login(_root, _args) do
    user = Repo.one(User)
    {:ok, token, claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    {:ok, %{user: Repo.one(User), token: token}}
  end
end
