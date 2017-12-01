defmodule SanbaseWeb.Auth.Resolver do
  require Logger

  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Auth.Ethauth
  alias Sanbase.Repo

  def current_user(_root, %{context: %{current_user: user}}) do
    {:ok, user}
  end

  def current_user(_root, _args), do: {:ok, nil}

  def eth_login(_root, %{signature: signature, address: address, address_hash: address_hash} = args) do
    with true <- Ethauth.verify_signature(signature, address, address_hash),
    {:ok, user} <- fetch_user(args, Repo.get_by(EthAccount, address: address)) do
      {:ok, user}
    else
      {:error, reason} ->
        Logger.warn("Login failed: #{reason}")

        {:error, :login_failed}
      _ ->
        Logger.warn("Login failed: invalid signature")
        {:error, :login_failed}
    end
  end

  # No eth account and there is a user logged in
  defp fetch_user(%{address: address, context: %{current_user: current_user}}, nil) do
    %EthAccount{user_id: current_user.id, address: address}
    |> Repo.insert!

    {:ok, current_user}
  end

  # No eth account and no user logged in
  defp fetch_user(%{address: address}, nil) do
    Multi.new
    |> Multi.insert(:add_user, %User{username: address})
    |> Multi.run(:add_eth_account, fn %{add_user: %User{id: id}} ->
      eth_account = Repo.insert(%EthAccount{user_id: id, address: address})

      {:ok, eth_account}
    end)
    |> case do
      {:ok, %{add_user: user}} -> user
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # Existing eth account, login as the user of the eth account
  defp fetch_user(_, %EthAccount{user_id: user_id}) do
    {:ok, Repo.get!(User, user_id)}
  end
end
