defmodule Sanbase.Accounts.User.SanBalance do
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Accounts.{User, EthAccount}

  @san_balance_cache_seconds 60 * 5

  def san_balance_cache_stale?(%User{san_balance_updated_at: nil}), do: true

  def san_balance_cache_stale?(%User{san_balance_updated_at: san_balance_updated_at}) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    Timex.diff(naive_now, san_balance_updated_at, :seconds) > @san_balance_cache_seconds
  end

  def update_san_balance_changeset(user) do
    user = Repo.preload(user, :eth_accounts)
    san_balance = san_balance_for_eth_accounts(user)
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> change(
      san_balance_updated_at: naive_now,
      san_balance: san_balance
    )
  end

  @spec san_balance(%User{}) :: {:ok, float()} | {:ok, nil} | {:error, String.t()}
  def san_balance(%User{test_san_balance: test_san_balance})
      when not is_nil(test_san_balance) do
    {:ok, test_san_balance |> Sanbase.Math.to_float()}
  end

  def san_balance(%User{san_balance: san_balance} = user) do
    if san_balance_cache_stale?(user) do
      update_san_balance_changeset(user)
      |> Repo.update()
      |> case do
        {:ok, %{san_balance: san_balance}} ->
          {:ok, san_balance |> Sanbase.Math.to_float()}

        {:error, error} ->
          {:error, error}
      end
    else
      {:ok, san_balance |> Sanbase.Math.to_float()}
    end
  end

  @spec san_balance_or_zero(%User{}) :: float
  def san_balance_or_zero(%User{} = user) do
    case san_balance(user) do
      {:ok, san_balance} -> san_balance
      _ -> 0
    end
  end

  defp san_balance_for_eth_accounts(%User{eth_accounts: eth_accounts, san_balance: san_balance}) do
    eth_accounts_balances =
      eth_accounts
      |> Enum.map(&EthAccount.san_balance/1)
      |> Enum.reject(&is_nil/1)

    case Enum.member?(eth_accounts_balances, :error) do
      true -> san_balance
      _ -> Enum.reduce(eth_accounts_balances, 0, &Kernel.+/2)
    end
  end
end
