defmodule Sanbase.Transfers do
  alias Sanbase.Model.Project

  alias Sanbase.Transfers.{EthTransfers, Erc20Transfers, BtcTransfers}

  def incoming_transfers_summary(slug, address, from, to, opts) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, "ETH", _, _} ->
        EthTransfers.incoming_transfers_summary(address, from, to, opts)

      {:ok, contract, decimals, "ETH"} ->
        Erc20Transfers.incoming_transfers_summary(address, contract, decimals, from, to, opts)

      _ ->
        {:error, "incoming_transfers_summary/5 is not supported for slug #{slug}"}
    end
  end

  def outgoing_transfers_summary(slug, address, from, to, opts) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, "ETH", _, _} ->
        EthTransfers.outgoing_transfers_summary(address, from, to, opts)

      {:ok, contract, decimals, "ETH"} ->
        Erc20Transfers.outgoing_transfers_summary(address, contract, decimals, from, to, opts)

      _ ->
        {:error, "outgoing_transfers_summary/5 is not supported for slug #{slug}"}
    end
  end

  def blockchain_address_transaction_volume(slug, address_or_addresses, from, to) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, contract, decimals, "ETH"} ->
        to_addresses_list(address_or_addresses)
        |> Erc20Transfers.blockchain_address_transaction_volume(
          contract,
          decimals,
          from,
          to
        )
    end
  end

  def blockchain_address_transaction_volume_over_time(
        slug,
        address_or_addresses,
        from,
        to,
        interval
      ) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, "ETH", _, _} ->
        to_addresses_list(address_or_addresses)
        |> EthTransfers.blockchain_address_transaction_volume_over_time(from, to, interval)

      {:ok, contract, decimals, "ETH"} ->
        to_addresses_list(address_or_addresses)
        |> Erc20Transfers.blockchain_address_transaction_volume_over_time(
          contract,
          decimals,
          from,
          to,
          interval
        )
    end
  end

  def top_wallet_transfers(
        slug,
        address_or_addresses,
        from,
        to,
        page,
        page_size,
        transaction_type
      ) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, "BTC", _, _} ->
        to_addresses_list(address_or_addresses)
        |> BtcTransfers.top_wallet_transfers(from, to, page, page_size, transaction_type)

      {:ok, "ETH", _, _} ->
        to_addresses_list(address_or_addresses)
        |> EthTransfers.top_wallet_transfers(from, to, page, page_size, transaction_type)

      {:ok, contract, decimals, "ETH"} ->
        to_addresses_list(address_or_addresses)
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

  # Private functions

  defp to_addresses_list(address_or_addresses) do
    address_or_addresses
    |> List.wrap()
    |> Enum.map(&Sanbase.BlockchainAddress.to_internal_format/1)
  end
end
