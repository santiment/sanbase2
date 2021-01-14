defmodule Sanbase.Auth.User.UniswapSanStaking do
  import Ecto.Changeset
  import Sanbase.SmartContracts.Utils, only: [format_number: 2]

  alias Sanbase.Repo
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.SmartContracts.UniswapPair

  def update_san_staked_all_users() do
    User.fetch_all_users_with_eth_account()
    |> Enum.each(&update_san_staked_user/1)
  end

  def update_san_staked_user(user) do
    san_staked = fetch_san_staked_user(user)
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> change(
      san_staked_updated_at: naive_now,
      san_staked: san_staked
    )
    |> Repo.update()
  end

  def fetch_san_staked_user(user) do
    user = user |> Repo.preload(:eth_accounts)

    Enum.reduce(user.eth_accounts, 0.0, fn %EthAccount{address: address}, acc ->
      UniswapPair.all_pair_contracts()
      |> Enum.map(&san_staked_address(address, &1))
      |> List.insert_at(-1, acc)
      |> Enum.sum()
    end)
  end

  def san_staked_address(address, contract) do
    decimals = UniswapPair.decimals(contract)
    san_position_in_pair = UniswapPair.get_san_position(contract)

    total_san_staked =
      UniswapPair.reserves(contract)
      |> Enum.at(san_position_in_pair)
      |> format_number(decimals)

    address_staked_tokens =
      UniswapPair.balance_of(address, contract)
      |> format_number(decimals)

    total_staked_tokens =
      UniswapPair.total_supply(contract)
      |> format_number(decimals)

    if total_staked_tokens > 0 do
      part_of_all_for_address = address_staked_tokens / total_staked_tokens
      part_of_all_for_address * total_san_staked
    else
      0.0
    end
  end
end
