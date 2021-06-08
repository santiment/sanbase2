defmodule Sanbase.Transfers do
  alias Sanbase.Model.Project

  alias Sanbase.Transfers.{EthTransfers, Erc20Transfers, BtcTransfers}

  def top_wallet_transfers(slug, address, from, to, page, page_size, transaction_type) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, "BTC", _, _} ->
        List.wrap(address)
        |> BtcTransfers.top_wallet_transfers(from, to, page, page_size, transaction_type)

      {:ok, "ETH", _, _} ->
        List.wrap(address)
        |> Enum.map(&Sanbase.BlockchainAddress.to_internal_format/1)
        |> EthTransfers.top_wallet_transfers(from, to, page, page_size, transaction_type)

      {:ok, contract, decimals, "ETH"} ->
        List.wrap(address)
        |> Enum.map(&Sanbase.BlockchainAddress.to_internal_format/1)
        |> Erc20Transfers.top_wallet_transfers(
          contract,
          from,
          to,
          decimals,
          page,
          page_size,
          transaction_type
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

  def top_transfers(slug, from, to, page, page_size, opts \\ [])

  def top_transfers(slug, from, to, page, page_size, opts) do
    excluded_addresses = Keyword.get(opts, :excluded_addresses, [])

    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, "ETH", _, _} ->
        EthTransfers.top_transfers(from, to, page, page_size)

      {:ok, "BTC", _, _} ->
        excluded_addresses = Keyword.get(opts, :excluded_addresses, [])
        BtcTransfers.top_transfers(from, to, page, page_size, excluded_addresses)

      {:ok, contract, decimals, "ETH"} ->
        Erc20Transfers.top_transfers(
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
