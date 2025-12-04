defmodule Sanbase.ExternalServices.Coinmarketcap.ContractDecimalsUpdater do
  @moduledoc """
  Updates the contract addresses decimals based on CoinMarketCap metadata v2.
  """

  alias Sanbase.Project.ContractAddress

  import Ecto.Query
  require Logger

  def work() do
    get_contracts_without_decimals()
    |> group_by_infrastructure()
    |> Enum.each(fn {chain, contract_addresses} ->
      addresses = Enum.map(contract_addresses, & &1.address)

      with {:ok, decimals_map} <- allium_get_decimals(addresses, chain) do
        fill_decimals(contract_addresses, decimals_map)
      end
    end)
  end

  def run_report_for_existing_decimals() do
    ContractAddress.all_with_infrastructure()
    |> Enum.reject(fn ca -> is_nil(ca.decimals) end)
    |> group_by_infrastructure()
    |> Enum.each(fn {chain, contract_addresses} ->
      addresses = Enum.map(contract_addresses, & &1.address)

      with {:ok, decimals_map} <- allium_get_decimals(addresses, chain) do
        Enum.each(contract_addresses, fn ca ->
          address_downcased = String.downcase(ca.address)

          decimals = Map.get(decimals_map, address_downcased)

          if is_integer(decimals) and decimals != ca.decimals do
            Logger.info(
              "Discrepancy found for contract address (id: #{ca.id}) #{ca.address} on chain #{chain}: existing decimals #{ca.decimals}, Allium decimals #{decimals}"
            )
          end
        end)
      end
    end)
  end

  defp fill_decimals(contract_addresses, decimals_map) do
    Enum.each(contract_addresses, fn ca ->
      address_downcased = String.downcase(ca.address)

      with decimals when is_integer(decimals) and decimals in 0..18 <-
             Map.get(decimals_map, address_downcased) do
        changeset =
          ContractAddress.changeset(ca, %{
            decimals: decimals,
            decimals_scrape_attempted_at: DateTime.utc_now(:second)
          })

        case Sanbase.Repo.update(changeset) do
          {:ok, _updated_ca} ->
            Logger.info(
              "Updated decimals for contract address (id: #{ca.id}) #{ca.address} on to #{decimals} (previously #{ca.decimals})"
            )

            :ok

          {:error, changeset} ->
            Logger.error(
              "Failed to update decimals for contract address #{ca.address}: #{inspect(changeset.errors)}"
            )
        end
      end
    end)
  end

  defp get_contracts_without_decimals() do
    twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24, :hour)

    ContractAddress.all_with_infrastructure()
    |> Enum.filter(fn ca ->
      (is_nil(ca.decimals) or ca.decimals == 0) and
        (is_nil(ca.decimals_scrape_attempted_at) or
           DateTime.compare(ca.decimals_scrape_attempted_at, twenty_four_hours_ago) == :lt)
    end)
  end

  defp group_by_infrastructure(contracts) do
    contracts
    |> Enum.group_by(fn ca -> infrastructure_to_chain(ca.project.infrastructure.code) end)
    |> Enum.reject(fn {chain, _} -> is_nil(chain) end)
  end

  defp infrastructure_to_chain(infrastructure_code) do
    case infrastructure_code do
      "ETH" -> "ethereum"
      "Arbitrum" -> "arbitrum"
      "Optimism" -> "optimism"
      "Avalanche" -> "avalanche"
      "Polygon" -> "polygon"
      "Base" -> "base"
      "Solana" -> "solana"
      _ -> nil
    end
  end

  def allium_get_decimals(addresses, chain) when is_list(addresses) and is_binary(chain) do
    api_key = System.get_env("ALLIUM_API_KEY")

    # Allium seems to lowercase all case-insensitive addresses.
    addresses =
      if chain in ["solana"], do: addresses, else: Enum.map(addresses, &String.downcase/1)

    contracts = addresses |> Enum.map(&~s|'#{&1}'|) |> Enum.join(",")

    payload = %{chain: chain, contracts: contracts}

    headers = [{"X-API-KEY", api_key}, {"Content-Type", "application/json"}]

    case Req.post(url(chain), json: payload, headers: headers) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        # It is ok to lowercase solana here as we use this table only for lookups
        # We will also lowercase the address when it is looked up.
        # This way the code is simpler with less branching
        map = Map.new(data, &{String.downcase(&1["address"]), &1["decimals"]})
        {:ok, map}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Allium API error: status #{status}, body: #{inspect(body)}")
        {:error, "Allium API error: #{status}"}

      {:error, error} ->
        Logger.error("Allium API request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp url(chain) do
    query = if chain == "solana", do: "dYNjPaB3Rk8kaRuNv18O", else: "L7Bn640totHX3wgz0TXy"
    "https://api.allium.so/api/v1/explorer/queries/#{query}/run"
  end
end
