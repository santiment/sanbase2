defmodule SanbaseWeb.Graphql.Resolvers.ProjectBalanceResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress
  }

  alias SanbaseWeb.Graphql.SanbaseDataloader

  defp current_balance_loader(loader, address_or_addresses, selector) do
    address_or_addresses
    |> List.wrap()
    |> Enum.reduce(loader, fn address, loader ->
      loader
      |> Dataloader.load(
        SanbaseDataloader,
        :address_selector_current_balance,
        {address, selector}
      )
    end)
  end

  defp current_combined_balance_from_loader(loader, address_or_addresses, selector) do
    balances =
      address_or_addresses
      |> List.wrap()
      |> Enum.map(fn address ->
        balance =
          loader
          |> Dataloader.get(
            SanbaseDataloader,
            :address_selector_current_balance,
            {address, selector}
          )

        balance || 0.0
      end)

    {:ok, Enum.sum(balances)}
  end

  def eth_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    {:ok, eth_addresses} =
      project
      |> Project.eth_addresses()

    selector = %{slug: "ethereum"}

    loader
    |> current_balance_loader(eth_addresses, selector)
    |> on_load(&current_combined_balance_from_loader(&1, eth_addresses, selector))
  end

  def btc_balance(_root, _args, _resolution) do
    # Note: Deprecated
    {:ok, nil}
  end

  def usd_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    {:ok, eth_addresses} = Project.eth_addresses(project)

    loader
    |> usd_balance_loader(eth_addresses)
    |> on_load(&usd_balance_from_loader(&1, eth_addresses, project))
  end

  def usd_balance_loader(loader, eth_addresses) do
    loader
    |> current_balance_loader(eth_addresses, %{slug: "ethereum"})
    |> Dataloader.load(SanbaseDataloader, :last_price_usd, "ethereum")
  end

  def usd_balance_from_loader(loader, eth_addresses, project) do
    with {:ok, eth_balance} <-
           current_combined_balance_from_loader(loader, eth_addresses, %{slug: "ethereum"}),
         eth_price_usd when not is_nil(eth_price_usd) <-
           Dataloader.get(loader, SanbaseDataloader, :last_price_usd, "ethereum") do
      {:ok, eth_balance * eth_price_usd}
    else
      error ->
        Logger.warning(
          "Cannot calculate USD balance for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        {:nocache, {:ok, nil}}
    end
  end

  def eth_address_balance(%ProjectEthAddress{address: address}, _args, %{
        context: %{loader: loader}
      }) do
    address = Sanbase.BlockchainAddress.to_internal_format(address)
    selector = %{slug: "ethereum"}

    loader
    |> current_balance_loader(address, selector)
    |> on_load(&current_combined_balance_from_loader(&1, address, selector))
  end
end
