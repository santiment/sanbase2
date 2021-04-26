defmodule Sanbase.Transfers do
  alias Sanbase.Model.Project

  alias Sanbase.Transfers.{EthTransfers, Erc20Transfers, BtcTransfers}

  def top_transactions(slug, from, to, page, page_size, opts \\ [])

  def top_transactions("ethereum", from, to, page, page_size, opts) do
    _excluded_addresses = Keyword.get(opts, :excluded_addresses, [])
    EthTransfers.top_transactions(from, to, page, page_size)
  end

  def top_transactions("bitcoin", from, to, page, page_size, opts) do
    excluded_addresses = Keyword.get(opts, :excluded_addresses, [])
    BtcTransfers.top_transactions(from, to, page, page_size, excluded_addresses)
  end

  def top_transactions(slug, from, to, page, page_size, opts) do
    excluded_addresses = Keyword.get(opts, :excluded_addresses, [])

    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, contract, decimals, "ETH"} ->
        Erc20Transfers.top_transactions(
          contract,
          from,
          to,
          decimals,
          page,
          page_size,
          excluded_addresses
        )

      {:ok, _, _, infrastructure} ->
        {:error,
         """
         Project with slug #{slug} has #{infrastructure} infrastructure which \
         does not have support for top transactions
         """}

      {:error, {:missing_contract, _} = error} ->
        {:error, error}
    end
  end
end
