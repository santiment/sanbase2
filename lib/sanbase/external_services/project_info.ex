defmodule Sanbase.ExternalServices.ProjectInfo do
  @moduledoc """
  # Fetch information about a project

  This module combies the logic from several external and internal services
  in order to scrape as much information about a project as possible. All the
  fields that are scraped can be seen in the struct that the module defines.

  There is also a function, which allows to update the project with the
  collected information.
  """
  defstruct [
    :coinmarketcap_id,
    :name,
    :website_link,
    :github_link,
    :main_contract_address,
    :ticker,
    :creation_transaction,
    :contract_block_number,
    :contract_abi
  ]

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.ExternalServices.Etherscan
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.InternalServices.Parity
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, Ico}

  require Logger

  def fetch_coinmarketcap_info(%ProjectInfo{coinmarketcap_id: coinmarketcap_id} = project_info) do
    Coinmarketcap.Scraper.fetch_project_page(coinmarketcap_id)
    |> Coinmarketcap.Scraper.parse_project_page(project_info)
  end

  def fetch_contract_info(%ProjectInfo{main_contract_address: nil} = project_info), do: project_info

  def fetch_contract_info(%ProjectInfo{main_contract_address: main_contract_address} = project_info) do
    Etherscan.Scraper.fetch_address_page(main_contract_address)
    |> Etherscan.Scraper.parse_address_page(project_info)
    |> fetch_block_number()
    |> fetch_abi()
  end

  def update_project(project_info, project) do
    Repo.transaction fn ->
      project
      |> find_or_create_initial_ico()
      |> Ico.changeset(Map.from_struct(project_info))
      |> Repo.insert_or_update!

      # Don't automatically update an already existing project's name - it is a UK when importing form other sources
      project_attrs = project_info
      |> Map.from_struct()
      |> Map.delete(:name)

      project
      |> Project.changeset(project_attrs)
      |> Repo.update!
    end
  end

  defp find_or_create_initial_ico(project) do
    case Project.initial_ico(project) do
      nil -> %Ico{project_id: project.id}
      ico -> ico
    end
  end

  defp fetch_block_number(%ProjectInfo{creation_transaction: creation_transaction} = project_info) do
    %{"blockNumber" => "0x" <> block_number_hex} = Parity.get_transaction_by_hash!(creation_transaction)

    {block_number, ""} = Integer.parse(block_number_hex, 16)

    %ProjectInfo{project_info | contract_block_number: block_number}
  end

  defp fetch_abi(%ProjectInfo{main_contract_address: main_contract_address} = project_info) do
    case Etherscan.Requests.get_abi(main_contract_address) do
      {:ok, abi} -> %ProjectInfo{project_info | contract_abi: abi}
      {:error, error} ->
        Logger.info("Can't get the ABI for address #{main_contract_address}: #{error}")
        project_info
    end
  end
end
