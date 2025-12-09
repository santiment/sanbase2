defmodule Sanbase.ExternalServices.Coinmarketcap.MetadataExporter do
  @moduledoc """
  Exports the CoinMarketCap metadata v2 to a JSON file.
  """

  require Logger

  import Ecto.Query

  import Sanbase.ExternalServices.Coinmarketcap.Utils,
    only: [
      san_contract_to_project_map: 0,
      cmc_contract_to_cmc_id_map: 0,
      cmc_id_to_project_map: 0,
      cmc_platform_name_to_infrastructure: 0,
      get_cmc_metadata: 1
    ]

  @url "/v2/cryptocurrency/info"

  def work() do
    get_slugs()
    |> Enum.chunk_every(100)
    |> Enum.each(fn slugs -> do_work(slugs) end)
  end

  def do_work(slugs) do
    case get_cmc_metadata(slugs) do
      {:ok, body} -> {:ok, process_body(body)}
      {:error, reason} -> {:error, reason}
    end
  end

  def process_body(body) do
    body["data"]
    |> Enum.map(fn {_slug, data} ->
      %{"slug" => cmc_id, "contract_address" => contracts} = data
      project = cmc_id_to_project_map()[cmc_id]
      process_project_data(project, contracts)
    end)
  end

  def process_project_data(nil, []), do: :ok
  def process_project_data(_cmc_id, []), do: :ok
  def process_project_data(%{infrastructure: nil}, []), do: :ok

  @supported_infrastructures cmc_platform_name_to_infrastructure() |> Map.values()
  def process_project_data(%{infrastructure: %{code: project_infr}} = project, contracts)
      when project_infr in @supported_infrastructures do
    cmc_contracts_for_project =
      Enum.map(contracts, fn contract ->
        %{"contract_address" => contract_address, "platform" => platform_map} = contract

        platform_name = platform_map["name"]

        infrastructure =
          Map.get(cmc_platform_name_to_infrastructure(), platform_name, "<Not Mapped>")

        %{
          "original_contract_address" => contract_address,
          "contract_address" => String.downcase(contract_address),
          "infrastructure" => infrastructure
        }
      end)
      |> Enum.filter(&(&1["infrastructure"] == project_infr))

    san_contracts_for_project =
      Enum.map(project.contract_addresses, fn ca ->
        %{
          "contract_address" => String.downcase(ca.address),
          "original_contract_address" => ca.address,
          "infrastructure" => project.infrastructure.code
        }
      end)

    new_addresses =
      Enum.map(cmc_contracts_for_project, & &1["contract_address"]) --
        Enum.map(san_contracts_for_project, & &1["contract_address"])

    extra_addresses =
      Enum.map(san_contracts_for_project, & &1["contract_address"]) --
        Enum.map(cmc_contracts_for_project, & &1["contract_address"])

    if new_addresses != [] or extra_addresses != [] do
      IO.puts("============================================")
      IO.puts("Project Name: #{project.name}")
      IO.puts("New addresses to be added to Santiment:")
      Enum.each(new_addresses, fn addr -> IO.puts("  - #{addr}") end)

      IO.puts("Addresses present in Santiment but missing from CMC:")
      Enum.each(extra_addresses, fn addr -> IO.puts("  - #{addr}") end)
    end
  end

  def process_project_data(_project_with_not_tracked_infr, _contracts), do: :ok

  def get_slugs() do
    data =
      Sanbase.Project.List.projects(preload: [:latest_coinmarketcap_data])
      |> Enum.filter(& &1.coinmarketcap_id)
      |> Enum.map(& &1.coinmarketcap_id)
  end
end
