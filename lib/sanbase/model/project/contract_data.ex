defmodule Sanbase.Model.Project.ContractData do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def contract_info_by_slug("ethereum"), do: {:ok, "ETH", 18}
  def contract_info_by_slug("bitcoin"), do: {:ok, "BTC", 8}

  def contract_info_by_slug(slug) do
    from(p in Project,
      where: p.coinmarketcap_id == ^slug,
      select: {p.main_contract_address, p.token_decimals}
    )
    |> Repo.one()
    |> case do
      {contract, token_decimals} when is_binary(contract) ->
        {:ok, String.downcase(contract), token_decimals || 0}

      _ ->
        {:error, {:missing_contract, "Can't find contract address of project with slug: #{slug}"}}
    end
  end

  def contract_address(%Project{} = project) do
    case contract_info(project) do
      {:ok, address, _} -> address
      _ -> nil
    end
  end

  # Internally when we have a table with blockchain related data
  # contract address is used to identify projects. In case of ethereum
  # the contract address contains simply 'ETH'
  def contract_info(%Project{coinmarketcap_id: "ethereum"}), do: {:ok, "ETH", 18}
  def contract_info(%Project{coinmarketcap_id: "bitcoin"}), do: {:ok, "BTC", 8}

  def contract_info(%Project{
        main_contract_address: main_contract_address,
        token_decimals: token_decimals
      })
      when not is_nil(main_contract_address) do
    {:ok, String.downcase(main_contract_address), token_decimals || 0}
  end

  def contract_info(%Project{} = project) do
    {:error, {:missing_contract, "Can't find contract address of #{Project.describe(project)}"}}
  end

  def contract_info(data) do
    {:error, "Not valid project type provided to contract_info - #{inspect(data)}"}
  end
end
