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
      |> Ecto.Multi.run(:add_eth_account, fn _repo, %{add_user: %User{id: id}} ->
        EthAccount.create(%{user_id: id, address: address})
      end)
      |> Repo.transaction()

    case multi_result do
      {:ok, %{add_user: user}} ->
        {:ok, user}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  @spec add_eth_account(%User{}, String.t()) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}
  def add_eth_account(%User{id: user_id}, address) do
    EthAccount.create(%{user_id: user_id, address: address})
  end

  @doc ~s"""
  An EthAccount can be removed only if there is another mean to login - an email address
  or another ethereum address set. If the address that is being removed is the only
  address and there is no email, the user account will be lost as there won't be
  any way to log in
  """
  @spec remove_eth_account(%User{}, String.t()) :: true | {:error, String.t()}
  def remove_eth_account(%User{id: user_id} = user, address) do
    if can_remove_eth_account?(user, address) do
      case EthAccount.delete_user_address(user_id, address) do
        {1, _} -> true
        {0, _} -> {:error, "Address #{address} does not exist or is not owned by user #{user_id}"}
      end
    else
      {:error,
       "Cannot remove ethereum address #{address}. There must be an email or other ethereum address set."}
    end
  end

  # Helpers

  defp can_remove_eth_account?(%User{id: user_id, email: email}, address) do
    count_other_accounts =
      EthAccount.by_user(user_id)
      |> Enum.map(& &1.address)
      |> Enum.reject(&(&1 == address))
      |> Enum.uniq()
      |> Enum.count()

    count_other_accounts > 0 or not is_nil(email)
  end
end
