defmodule Sanbase.Accounts do
  alias Sanbase.Repo
  alias __MODULE__.{User, EthAccount}

  def get_user(user_id_or_ids) do
    User.by_id(user_id_or_ids)
  end

  def get_user!(user_id_or_ids) do
    case User.by_id(user_id_or_ids) do
      {:ok, user} -> user
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
  Create a new user with an ETH address. The address is created and linked in the
  ETH Accounts, but also set as the username.
  """
  @spec create_user_with_eth_address(String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user_with_eth_address(address) when is_binary(address) do
    multi_result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:add_user, fn _, _ -> User.create(%{username: address}) end)
      |> Ecto.Multi.run(:add_eth_account, fn _repo, %{add_user: %User{} = user} ->
        EthAccount.create(user.id, address)
      end)
      |> Repo.transaction()

    case multi_result do
      {:ok, %{add_user: user}} ->
        {:ok, user}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end
end
