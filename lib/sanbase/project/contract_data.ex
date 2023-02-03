defmodule Sanbase.Project.ContractData do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Project

  @special_cases %{
    "ethereum" => %{contract_address: "ETH", decimals: 18},
    "bitcoin" => %{contract_address: "BTC", decimals: 8},
    "bitcoin-cash" => %{contract_address: "BCH", decimals: 8},
    "litecoin" => %{contract_address: "LTC", decimals: 8},
    "xrp" => %{contract_address: "XRP", decimals: 0},
    "binance-coin" => %{contract_address: "BNB", decimals: 0}
  }

  @special_case_slugs @special_cases |> Map.keys()

  def special_case_slugs(), do: @special_case_slugs

  def special_cases(), do: @special_cases

  def has_contract_address?(%Project{} = project) do
    is_binary(contract_address(project))
  end

  # Internally when we have a table with blockchain related data
  # contract address is used to identify projects. In case of ethereum
  # the contract address contains simply 'ETH'

  @spec contract_info(%Project{}, Keyword.t()) ::
          {:ok, contract, decimals} | {:error, tuple()}
        when contract: String.t(), decimals: non_neg_integer()
  def contract_info(project, opts \\ [])

  for {slug, %{contract_address: contract, decimals: decimals}} <- @special_cases do
    def contract_info(%Project{slug: unquote(slug)}, _opts) do
      {:ok, unquote(contract), unquote(decimals)}
    end
  end

  def contract_info(%Project{} = project, opts) do
    case Repo.preload(project, [:contract_addresses]) do
      %Project{contract_addresses: [_ | _] = list} ->
        contract = contracts_list_to_contract(list, opts)
        {:ok, String.downcase(contract.address), contract.decimals || 0}

      _ ->
        {:error,
         {:missing_contract, "Can't find contract address of #{Project.describe(project)}"}}
    end
  end

  def contract_info(data, _opts) do
    {:error, "Not valid project type provided to contract_info - #{inspect(data)}"}
  end

  @spec contract_info_by_slug(String.t(), Keyword.t()) ::
          {:ok, contract, decimals} | {:error, tuple()}
        when contract: String.t(), decimals: non_neg_integer()
  def contract_info_by_slug(slug, opts \\ [])

  for {slug, %{contract_address: contract, decimals: decimals}} <- @special_cases do
    def contract_info_by_slug(unquote(slug), _opts),
      do: {:ok, unquote(contract), unquote(decimals)}
  end

  def contract_info_by_slug(slug, opts) do
    case contract_addresses(slug) do
      [_ | _] = list ->
        contract = contracts_list_to_contract(list, opts)
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
  @spec contract_info_infrastructure_by_slug(String.t(), Keyword.t()) ::
          {:ok, contract, decimals, infrastructure} | {:error, {:missing_contract, String.t()}}
        when contract: String.t(), decimals: non_neg_integer(), infrastructure: String.t()
  def contract_info_infrastructure_by_slug(slug, opts \\ [])

  for {slug, %{contract_address: contract, decimals: decimals}} <-
        @special_cases do
    def contract_info_infrastructure_by_slug(unquote(slug), _opts),
      do: {:ok, unquote(contract), unquote(decimals), unquote(contract)}
  end

  def contract_info_infrastructure_by_slug(slug, opts) do
    Project.by_slug(slug,
      preload?: true,
      only_preload: [:contract_addresses, :infrastructure]
    )
    |> case do
      %Project{contract_addresses: [_ | _] = list, infrastructure: %{code: infr_code}} ->
        contract = contracts_list_to_contract(list, opts)
        {:ok, String.downcase(contract.address), contract.decimals || 0, infr_code}

      _ ->
        {:error,
         {:missing_contract,
          "Can't find contract address or infrastructure of project with slug: #{slug}"}}
    end
  end

  def contract_address(project, opts \\ [])

  for {slug, %{contract_address: contract}} <- @special_cases do
    def contract_address(%Project{slug: unquote(slug)}, _opts), do: unquote(contract)
  end

  def contract_address(%Project{} = project, opts) do
    case contract_info(project, opts) do
      {:ok, address, _} -> address
      _ -> nil
    end
  end

  defp contracts_list_to_contract(list, opts) do
    case Keyword.get(opts, :contract_type, :main_contract) do
      :main_contract ->
        Project.ContractAddress.list_to_main_contract_address(list)

      :latest_onchain_contract ->
        Project.ContractAddress.list_to_latest_onchain_contract_address(list)
    end
  end

  defp contract_addresses(slug) when is_binary(slug) do
    from(
      contract in Project.ContractAddress,
      inner_join: p in Project,
      on: contract.project_id == p.id,
      where: p.slug == ^slug
    )
    |> Repo.all()
  end
end
