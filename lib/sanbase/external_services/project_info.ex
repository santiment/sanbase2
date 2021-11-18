defmodule Sanbase.ExternalServices.ProjectInfo do
  @moduledoc """
    Fetch information about a project

    This module combies the logic from several external and internal services
    in order to scrape as much information about a project as possible. All the
    fields that are scraped can be seen in the struct that the module defines.

    There is also a function, which allows to update the project with the
    collected information.
  """
  defstruct [
    :slug,
    :name,
    :coinmarketcap_id,
    :website_link,
    :email,
    :reddit_link,
    :twitter_link,
    :btt_link,
    :blog_link,
    :github_link,
    :telegram_link,
    :slack_link,
    :facebook_link,
    :whitepaper_link,
    :main_contract_address,
    :ticker,
    :creation_transaction,
    :contract_block_number,
    :contract_abi,
    :etherscan_token_name,
    :token_decimals,
    :total_supply
  ]

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.ExternalServices.Etherscan
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.InternalServices.{EthNode, Ethauth}
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Tag

  require Logger

  def project_info_missing?(
        %Project{
          website_link: website_link,
          email: email,
          reddit_link: reddit_link,
          twitter_link: twitter_link,
          btt_link: btt_link,
          blog_link: blog_link,
          github_link: github_link,
          telegram_link: telegram_link,
          slack_link: slack_link,
          facebook_link: facebook_link,
          whitepaper_link: whitepaper_link,
          ticker: ticker,
          name: name,
          total_supply: total_supply
        } = project
      ) do
    !website_link or !email or !reddit_link or !twitter_link or !btt_link or !blog_link or
      !github_link or !telegram_link or !slack_link or !facebook_link or !whitepaper_link or
      !ticker or !name or !Project.has_contract_address?(project) or
      !total_supply
  end

  def from_project(project) do
    project_info =
      struct(__MODULE__, Map.to_list(project))
      |> struct(Map.to_list(find_or_create_initial_ico(project)))

    case Project.coinmarketcap_id(project) do
      nil -> project_info
      cmc_id -> %__MODULE__{project_info | coinmarketcap_id: cmc_id}
    end
  end

  def fetch_coinmarketcap_info(%ProjectInfo{coinmarketcap_id: nil} = project_info),
    do: project_info

  def fetch_coinmarketcap_info(%ProjectInfo{coinmarketcap_id: cmc_id} = project_info) do
    case Coinmarketcap.Scraper.fetch_project_page(cmc_id) do
      {:ok, scraped_project_info} ->
        Coinmarketcap.Scraper.parse_project_page(scraped_project_info, project_info)

      _ ->
        project_info
    end
  end

  def fetch_from_ethereum_node(%ProjectInfo{} = project_info) do
    project_info
    |> fetch_token_decimals()
    |> fetch_total_supply()
  end

  def fetch_contract_info(%ProjectInfo{main_contract_address: nil} = project_info),
    do: project_info

  def fetch_contract_info(
        %ProjectInfo{main_contract_address: main_contract_address} = project_info
      ) do
    Etherscan.Scraper.fetch_address_page(main_contract_address)
    |> Etherscan.Scraper.parse_address_page!(project_info)
    |> fetch_block_number()
    |> fetch_abi()
  end

  def fetch_etherscan_token_summary(%ProjectInfo{etherscan_token_name: nil} = project_info),
    do: project_info

  def fetch_etherscan_token_summary(
        %ProjectInfo{etherscan_token_name: etherscan_token_name} = project_info
      ) do
    Etherscan.Scraper.fetch_token_page(etherscan_token_name)
    |> Etherscan.Scraper.parse_token_page!(project_info)
  end

  def update_project(project_info, project) do
    Repo.transaction(fn ->
      project_info_map = Map.from_struct(project_info)

      project
      |> find_or_create_initial_ico()
      |> Ico.changeset(project_info_map)
      |> Repo.insert_or_update!()

      project
      |> maybe_add_contract_address(project_info_map)
      |> Project.changeset(project_info_map)
      |> Repo.update!()
    end)
    |> insert_tag(project_info)
  end

  defp maybe_add_contract_address(
         project,
         %{main_contract_address: contract_address} = project_info_map
       )
       when is_binary(contract_address) do
    label = if not Project.has_main_contract_addresses?(project), do: "main"

    contract_attrs = %{
      label: label,
      address: contract_address,
      decimals: project_info_map[:token_decimals]
    }

    # This returns a contract address, not a project. Do not use
    # the result of this but instead force the preload of the contracts
    # in the next call
    {:ok, _} = Project.ContractAddress.add_contract(project, contract_attrs)

    # The `project` won't have an up-to date list of contracts otherwise
    Repo.preload(project, [:contract_addresses], force: true)
  end

  defp maybe_add_contract_address(project, _project_info_map), do: project

  defp insert_tag({:ok, project}, project_info) do
    do_insert_tag(project, project_info)
    {:ok, project}
  end

  defp insert_tag({:error, reason}, _), do: {:error, reason}

  defp do_insert_tag(%Project{slug: slug}, %ProjectInfo{ticker: ticker})
       when not is_nil(ticker) and not is_nil(slug) do
    %Tag{name: ticker}
    |> Tag.changeset()
    |> Repo.insert()
    |> case do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warn("Cannot insert tag on project creation. Reason: #{inspect(changeset.errors)}")
    end
  end

  defp do_insert_tag(_, _), do: :ok

  defp find_or_create_initial_ico(project) do
    case Project.initial_ico(project) do
      nil -> %Ico{project_id: project.id}
      ico -> ico
    end
  end

  defp fetch_total_supply(
         %ProjectInfo{main_contract_address: contract, total_supply: nil} = project_info
       )
       when is_binary(contract) do
    case Ethauth.total_supply(contract) do
      {:ok, total_supply} -> %ProjectInfo{project_info | total_supply: total_supply}
      _ -> project_info
    end
  end

  defp fetch_total_supply(%ProjectInfo{} = project_info), do: project_info

  defp fetch_token_decimals(
         %ProjectInfo{main_contract_address: contract, token_decimals: nil} = project_info
       )
       when is_binary(contract) do
    case Ethauth.token_decimals(contract) do
      {:ok, token_decimals} -> %ProjectInfo{project_info | token_decimals: token_decimals}
      _ -> project_info
    end
  end

  defp fetch_token_decimals(%ProjectInfo{} = project_info), do: project_info

  defp fetch_block_number(%ProjectInfo{creation_transaction: nil} = project_info),
    do: project_info

  defp fetch_block_number(%ProjectInfo{creation_transaction: creation_transaction} = project_info) do
    %{"blockNumber" => "0x" <> block_number_hex} =
      EthNode.get_transaction_by_hash!(creation_transaction)

    {block_number, ""} = Integer.parse(block_number_hex, 16)

    %ProjectInfo{project_info | contract_block_number: block_number}
  end

  defp fetch_abi(%ProjectInfo{main_contract_address: main_contract_address} = project_info) do
    case Etherscan.Requests.get_abi(main_contract_address) do
      {:ok, abi} ->
        %ProjectInfo{project_info | contract_abi: abi}

      {:error, error} ->
        Logger.warn("Can't get the ABI for address #{main_contract_address}: #{inspect(error)}")
        project_info
    end
  end
end
