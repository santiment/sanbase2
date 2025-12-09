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
      cmc_id_to_projects_map: 0,
      cmc_platform_name_to_infrastructure: 0,
      save_cmc_metadata: 0,
      read_cmc_metadata: 0,
      special_contracts_lowercased: 0
    ]

  @url "/v2/cryptocurrency/info"

  def work(opts \\ []) do
    if Keyword.get(opts, :fetch_fresh_data, false) do
      save_cmc_metadata()
    end

    read_cmc_metadata()
    |> Enum.each(fn {_cmc_id, map} -> do_work(map) end)
  end

  @special_contracts_lowercased special_contracts_lowercased()
  def do_work(%{"slug" => cmc_id, "contract_address" => contracts}) do
    projects = cmc_id_to_projects_map()[cmc_id] || []

    Enum.each(projects, fn project ->
      cmc_has_contracts? = contracts != []
      project_has_infrastructure? = project && not is_nil(project.infrastructure)

      project_has_special_contract? =
        Enum.any?(project.contract_addresses, fn ca ->
          String.downcase(ca.address) in @special_contracts_lowercased
        end)

      if project_has_infrastructure? and cmc_has_contracts? and not project_has_special_contract? do
        process_project_data(project, contracts)
      end
    end)
  end

  @supported_infrastructures cmc_platform_name_to_infrastructure() |> Map.values()
  def process_project_data(
        %{infrastructure: %{code: project_infr}} = project,
        [_ | _] = contracts
      )
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

      IO.puts(
        "Project Name: #{project.name} (cmc id: #{project.coinmarketcap_id}, infr: #{project.infrastructure.code})"
      )

      Enum.each(new_addresses, fn addr ->
        if addr, do: IO.puts(IO.ANSI.green() <> "(+) #{addr}" <> IO.ANSI.reset())
      end)

      Enum.each(extra_addresses, fn addr ->
        if addr, do: IO.puts(IO.ANSI.red() <> "(-) #{addr}" <> IO.ANSI.reset())
      end)
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
