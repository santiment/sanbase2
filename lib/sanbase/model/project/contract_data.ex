defmodule Sanbase.Model.Project.ContractData do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.Project

  @special_cases %{
    "ethereum" => %{contract_address: "ETH", decimals: 18},
    "bitcoin" => %{contract_address: "BTC", decimals: 8},
    "bitcoin-cash" => %{contract_address: "BCH", decimals: 8},
    "litecoin" => %{contract_address: "LTC", decimals: 8},
    "eos" => %{contract_address: "eosio.token/EOS", decimals: 0},
    "ripple" => %{contract_address: "XRP", decimals: 0},
    "binance-coin" => %{contract_address: "BNB", decimals: 0}
  }

  @special_case_slugs @special_cases |> Map.keys()

  def special_case_slugs(), do: @special_case_slugs

  def special_cases(), do: @special_cases

  def has_contract_address?(%Project{} = project) do
    is_binary(contract_address(project))
  end

  @spec contract_info_by_slug(String.t()) :: {:ok, contract, decimals} | {:error, tuple()}
        when contract: String.t(), decimals: non_neg_integer()
  def contract_info_by_slug(slug)

  for {slug, %{contract_address: contract, decimals: decimals}} <- @special_cases do
    def contract_info_by_slug(unquote(slug)), do: {:ok, unquote(contract), unquote(decimals)}
  end

  def contract_info_by_slug(slug) do
    from(
      contract in Project.ContractAddress,
      inner_join: p in Project,
      on: contract.project_id == p.id,
      where: p.slug == ^slug
    )
    |> Repo.all()
    |> case do
      [_ | _] = list ->
        contract = Project.ContractAddress.list_to_main_contract_address(list)
        {:ok, String.downcase(contract.address), contract.decimals || 0}

      _ ->
        {:error, {:missing_contract, "Can't find contract address of project with slug: #{slug}"}}
    end
  end

  @doc ~s"""
  Return contract info and the real infrastructure. If the infrastructure is set
  to `own` in the database it will use the contract. Ethereum has ETH as contract,
  Bitcoin has BTC and so on, which is the real infrastructure
  """
  @spec contract_info_infrastructure_by_slug(String.t()) ::
          {:ok, contract, decimals, infrastructure} | {:error, String.t()}
        when contract: String.t(), decimals: non_neg_integer(), infrastructure: String.t()
  def contract_info_infrastructure_by_slug(slug)

  for {slug, %{contract_address: contract, decimals: decimals}} <-
        @special_cases do
    def contract_info_infrastructure_by_slug(unquote(slug)),
      do: {:ok, unquote(contract), unquote(decimals), unquote(contract)}
  end

  def contract_info_infrastructure_by_slug(slug) do
    from(
      p in Project,
      where: p.slug == ^slug,
      preload: [:infrastructure, :contract_addresses]
    )
    |> Repo.one()
    |> case do
      %Project{contract_addresses: [_ | _] = list, infrastructure: %{code: infr_code}} ->
        contract = Project.ContractAddress.list_to_main_contract_address(list)
        {:ok, String.downcase(contract.address), contract.decimals || 0, infr_code}

      _ ->
        {:error,
         {:missing_contract,
          "Can't find contract address or infrastructure of project with slug: #{slug}"}}
    end
  end

  for {slug, %{contract_address: contract}} <- @special_cases do
    def contract_address(%Project{slug: unquote(slug)}), do: unquote(contract)
  end

  for {slug, %{contract_address: contract}} <- @special_cases do
    def contract_addresses(%Project{slug: unquote(slug)}), do: [unquote(contract)]
  end

  def contract_address(%Project{} = project) do
    case contract_info(project) do
      {:ok, address, _} -> address
      _ -> nil
    end
  end

  def contract_addresses(%Project{} = project) do
    from(
      contract in Project.ContractAddress,
      where: contract.project_id == ^project.id,
      select: contract.address
    )
    |> Repo.all()
  end

  # Internally when we have a table with blockchain related data
  # contract address is used to identify projects. In case of ethereum
  # the contract address contains simply 'ETH'

  for {slug, %{contract_address: contract, decimals: decimals}} <- @special_cases do
    def contract_info(%Project{slug: unquote(slug)}) do
      {:ok, unquote(contract), unquote(decimals)}
    end
  end

  def contract_info(%Project{} = project) do
    case Repo.preload(project, [:contract_addresses]) do
      %Project{contract_addresses: [_ | _] = list} ->
        contract = Project.ContractAddress.list_to_main_contract_address(list)
        {:ok, String.downcase(contract.address), contract.decimals || 0}

      _ ->
        {:error,
         {:missing_contract, "Can't find contract address of #{Project.describe(project)}"}}
    end
  end

  def contract_info(data) do
    {:error, "Not valid project type provided to contract_info - #{inspect(data)}"}
  end
end
