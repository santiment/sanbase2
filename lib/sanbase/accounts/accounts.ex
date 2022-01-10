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

  def create_user_with_eth_address(address) when is_binary(address) do
    multi_result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :add_user,
        User.changeset(%User{}, %{
          username: address,
          salt: User.generate_salt(),
          first_login: true
        })
      )
      |> Ecto.Multi.run(:add_eth_account, fn _repo, %{add_user: %User{id: id}} ->
        eth_account =
          EthAccount.changeset(%EthAccount{}, %{user_id: id, address: address})
          |> Sanbase.Repo.insert()

        {:ok, eth_account}
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
