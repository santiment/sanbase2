defmodule SanbaseWeb.Graphql.Resolvers.ProjectBalanceResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress
  }

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.PriceStore

  def eth_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> eth_balance_loader(project)
    |> on_load(&eth_balance_from_loader(&1, project))
  end

  def eth_balance_loader(loader, project) do
    loader
    |> Dataloader.load(SanbaseRepo, :eth_addresses, project)
  end

  def eth_balance_from_loader(loader, project) do
    balance =
      loader
      |> Dataloader.get(SanbaseRepo, :eth_addresses, project)
      |> Stream.map(&ProjectEthAddress.balance(&1))
      |> Stream.reject(&is_nil/1)
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
      |> Stream.reject(&is_nil/1)
      |> Stream.map(& &1.latest_btc_wallet_data)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(&Decimal.to_float(&1.balance))
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
    |> Dataloader.load(PriceStore, "ETH_ethereum", :last)
    |> Dataloader.load(PriceStore, "BTC_bitcoin", :last)
  end

  def usd_balance_from_loader(loader, project) do
    with {:ok, eth_balance} <- eth_balance_from_loader(loader, project),
         {:ok, btc_balance} <- btc_balance_from_loader(loader, project),
         {eth_price_usd, _eth_price_btc} when not is_nil(eth_price_usd) <-
           Dataloader.get(loader, PriceStore, "ETH_ethereum", :last),
         {btc_price_usd, _btc_price_btc} when not is_nil(btc_price_usd) <-
           Dataloader.get(loader, PriceStore, "BTC_bitcoin", :last) do
      usd_balance_float = eth_balance * eth_price_usd + btc_balance * btc_price_usd

      {:ok, usd_balance_float}
    else
      error ->
        Logger.warn("Cannot calculate USD balance. Reason: #{inspect(error)}")
        {:ok, nil}
    end
  end

  def eth_address_balance(%ProjectEthAddress{} = eth_address, _args, %{
        context: %{loader: loader}
      }) do
    ProjectEthAddress.balance(eth_address)
  end
end
