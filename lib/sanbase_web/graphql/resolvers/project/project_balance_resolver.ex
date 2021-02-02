defmodule SanbaseWeb.Graphql.Resolvers.ProjectBalanceResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress
  }

  alias SanbaseWeb.Graphql.{SanbaseRepo, SanbaseDataloader}

  def eth_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> eth_balance_loader(project)
    |> on_load(&eth_balance_from_loader(&1, project))
  end

  def eth_balance_loader(loader, project) do
    loader
    |> Dataloader.load(SanbaseDataloader, :eth_balance, project)
  end

  def eth_balance_from_loader(loader, project) do
    addresses = Enum.map(project.eth_addresses, fn %{address: address} -> address end)

    balance =
      addresses
      |> Enum.map(fn address ->
        loader
        |> Dataloader.get(SanbaseDataloader, :eth_balance, address)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(0, &+/2)

    {:ok, balance}
  end

  def btc_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> btc_balance_loader(project)
    |> on_load(&btc_balance_from_loader(&1, project))
  end

  def btc_balance_loader(loader, project) do
    loader
    |> Dataloader.load(SanbaseRepo, :btc_addresses, project)
  end

  def btc_balance_from_loader(loader, project) do
    balance =
      loader
      |> Dataloader.get(SanbaseRepo, :btc_addresses, project)
      |> Enum.map(& &1.latest_btc_wallet_data)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(Decimal.to_float(&1.satoshi_balance) / 100_000_000))
      |> Enum.reduce(0, &+/2)

    {:ok, balance}
  end

  def usd_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> usd_balance_loader(project)
    |> on_load(&usd_balance_from_loader(&1, project))
  end

  def usd_balance_loader(loader, project) do
    loader
    |> eth_balance_loader(project)
    |> btc_balance_loader(project)
    |> Dataloader.load(SanbaseDataloader, :last_price_usd, "ethereum")
    |> Dataloader.load(SanbaseDataloader, :last_price_usd, "bitcoin")
  end

  def usd_balance_from_loader(loader, %Project{} = project) do
    with {:ok, eth_balance} <- eth_balance_from_loader(loader, project),
         {:ok, btc_balance} <- btc_balance_from_loader(loader, project),
         eth_price_usd when not is_nil(eth_price_usd) <-
           Dataloader.get(loader, SanbaseDataloader, :last_price_usd, "ethereum"),
         btc_price_usd when not is_nil(btc_price_usd) <-
           Dataloader.get(loader, SanbaseDataloader, :last_price_usd, "bitcoin") do
      usd_balance_float = eth_balance * eth_price_usd + btc_balance * btc_price_usd

      {:ok, usd_balance_float}
    else
      error ->
        Logger.warn(
          "Cannot calculate USD balance for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        {:nocache, {:ok, nil}}
    end
  end

  def eth_address_balance(%ProjectEthAddress{} = eth_address, _args, _resolution) do
    {:ok, ProjectEthAddress.balance(eth_address)}
  end
end
