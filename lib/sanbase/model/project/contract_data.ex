defmodule Sanbase.Model.Project.ContractData do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.Project

  @special_cases %{
    "ethereum" => %{main_contract_address: "ETH", token_decimals: 18, infrastructure: "ETH"},
    "bitcoin" => %{main_contract_address: "BTC", token_decimals: 8, infrastructure: "BTC"},
    "bitcoin-cash" => %{main_contract_address: "BCH", token_decimals: 8, infrastructure: "BCH"},
    "litecoin" => %{main_contract_address: "LTC", token_decimals: 8, infrastructure: "LTC"},
    "eos" => %{main_contract_address: "eosio.token/EOS", token_decimals: 0, infrastructure: "EOS"},
    "ripple" => %{main_contract_address: "XRP", token_decimals: 0, infrastructure: "XRP"},
    "binance-coin" => %{main_contract_address: "BNB", token_decimals: 0, infrastructure: "BNB"}
  }

  @special_case_slugs @special_cases |> Map.keys()

  def special_case_slugs(), do: @special_case_slugs

  def special_cases(), do: @special_cases

  @spec contract_info_by_slug(String.t()) :: {:ok, contract, decimals} | {:error, String.t()}
        when contract: String.t(), decimals: non_neg_integer()
  def contract_info_by_slug(slug)

  for {slug, %{main_contract_address: contract, token_decimals: decimals}} <- @special_cases do
    def contract_info_by_slug(unquote(slug)), do: {:ok, unquote(contract), unquote(decimals)}
  end

  def contract_info_by_slug(slug) do
    from(p in Project,
      where: p.slug == ^slug,
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

  @doc ~s"""
  Return contract info and the real infrastructure. If the infrastructure is set
  to `own` in the database it will use the contract. Ethereum has ETH as contract,
  Bitcoin has BTC and so on, which is the real infrastructure
  """
  @spec contract_info_infrastructure_by_slug(String.t()) ::
          {:ok, contract, decimals, infrastructure} | {:error, String.t()}
        when contract: String.t(), decimals: non_neg_integer(), infrastructure: String.t()
  def contract_info_infrastructure_by_slug(slug)

  for {slug, %{main_contract_address: contract, token_decimals: decimals, infrastructure: infr}} <-
        @special_cases do
    def contract_info_infrastructure_by_slug(unquote(slug)),
      do: {:ok, unquote(contract), unquote(decimals), unquote(infr)}
  end

  def contract_info_infrastructure_by_slug(slug) do
    from(p in Project,
      where: p.slug == ^slug,
      inner_join: infr in assoc(p, :infrastructure),
      select: {p.main_contract_address, p.token_decimals, infr.code}
    )
    |> Repo.one()
    |> case do
      {contract, token_decimals, infr} when is_binary(contract) ->
        {:ok, String.downcase(contract), token_decimals || 0, infr}

      _ ->
        {:error, {:missing_contract, "Can't find contract address of project with slug: #{slug}"}}
    end
  end

  for {slug, %{main_contract_address: contract}} <- @special_cases do
    def contract_address(%Project{slug: unquote(slug)}), do: unquote(contract)
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

  for {slug, %{main_contract_address: contract, token_decimals: decimals}} <- @special_cases do
    def contract_info(%Project{slug: unquote(slug)}) do
      {:ok, unquote(contract), unquote(decimals)}
    end
  end

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
