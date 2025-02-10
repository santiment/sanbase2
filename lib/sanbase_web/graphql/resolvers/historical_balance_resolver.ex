defmodule SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver do
  @moduledoc false
  import Absinthe.Resolution.Helpers

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 4]

  alias Sanbase.Clickhouse.HistoricalBalance
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def assets_held_by_address(_root, args, _resolution) do
    with {:ok, selector} <- args_to_address_selector(args) do
      case HistoricalBalance.assets_held_by_address(selector,
             show_assets_with_zero_balance: args.show_assets_with_zero_balance
           ) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} ->
          {:error, handle_graphql_error("Assets held by address", selector.address, error, description: "address")}
      end
    end
  end

  def usd_value_address_change(_root, args, _resolution) do
    with {:ok, selector} <- args_to_address_selector(args) do
      case HistoricalBalance.usd_value_address_change(selector, args.datetime) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} ->
          {:error, handle_graphql_error("USD value address change", selector.address, error, description: "address")}
      end
    end
  end

  def historical_balance(_root, %{from: from, to: to, interval: interval, address: address} = args, _resolution) do
    with {:ok, selector} <- args_to_historical_balance_selector(args) do
      selector
      |> HistoricalBalance.historical_balance(
        address,
        from,
        to,
        interval
      )
      |> maybe_handle_graphql_error(fn error ->
        handle_graphql_error(
          "Historical Balances",
          inspect(selector),
          error,
          description: "selector"
        )
      end)
    end
  end

  def address_historical_balance_change(_root, %{from: from, to: to, addresses: addresses} = args, _resolution) do
    with {:ok, selector} <- args_to_historical_balance_selector(args) do
      selector
      |> HistoricalBalance.balance_change(addresses, from, to)
      |> maybe_handle_graphql_error(fn error ->
        handle_graphql_error(
          "Historical Balance Change per Address",
          inspect(selector),
          error,
          description: "selector"
        )
      end)
    end
  end

  def miners_balance(root, %{} = args, resolution) do
    root
    |> MetricResolver.timeseries_data(
      args,
      Map.put(resolution, :source, %{metric: "miners_balance"})
    )
    |> Sanbase.Utils.Transform.rename_map_keys(
      old_key: :value,
      new_key: :balance
    )
  end

  def balance_usd(%{slug: slug, balance: balance}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :last_price_usd, slug)
    |> on_load(fn loader ->
      price_usd = Dataloader.get(loader, SanbaseDataloader, :last_price_usd, slug)

      {:ok, price_usd && balance * price_usd}
    end)
  end

  # Private functions

  defp args_to_historical_balance_selector(args) do
    case_result =
      case Map.get(args, :selector) do
        nil ->
          address = args.address
          infrastructure = Sanbase.BlockchainAddress.to_infrastructure(address)
          %{infrastructure: infrastructure, address: address}

        selector ->
          selector |> Map.put(:address, args[:address]) |> Map.put(:addresses, args[:addresses])
      end

    case_result
    |> validate_historical_balance_selector()
    |> case do
      {:ok, selector} -> {:ok, Map.drop(selector, [:address, :addresses])}
      {:error, error} -> {:error, error}
    end
  end

  defp args_to_address_selector(args) do
    case Map.get(args, :selector) do
      nil ->
        address = args.address
        infrastructure = Sanbase.BlockchainAddress.to_infrastructure(address)
        selector = %{infrastructure: infrastructure, address: address}
        {:ok, selector}

      selector ->
        {:ok, selector}
    end
  end

  defp validate_historical_balance_selector(%{infrastructure: "XRP"} = selector) do
    cond do
      not address_matches_regex?(selector, Sanbase.BlockchainAddress.xrp_regex()) ->
        {:error, "Invalid XRP address(es): #{format_address(selector)}"}

      not Map.has_key?(selector, :currency) ->
        {:error, "When getting data for the XRPL blockchain, the currency parameter is mandatory"}

      not Map.has_key?(selector, :issuer) ->
        {:error, "When getting data for the XRPL blockchain, the issuer parameter is mandatory"}

      selector.currency == "XRP" and selector.issuer != "XRP" ->
        {:error, "The only issuer for XRP is XRP"}

      true ->
        {:ok, selector}
    end
  end

  defp validate_historical_balance_selector(%{infrastructure: "ETH"} = selector) do
    if Regex.match?(Sanbase.BlockchainAddress.ethereum_regex(), selector.address) do
      {:ok, selector}
    else
      {:error, "Invalid Ethereum address: #{selector.address}"}
    end
  end

  defp validate_historical_balance_selector(%{infrastructure: "BTC"} = selector) do
    cond do
      not Regex.match?(Sanbase.BlockchainAddress.bitcoin_regex(), selector.address) ->
        {:error, "Invalid Bitcoin address: #{selector.address}"}

      selector[:slug] not in [nil, "bitcoin"] ->
        {:error, "When fetching Bitcoin historical balances, do not provide slug or provide the `bitcoin` slug."}

      true ->
        {:ok, selector}
    end
  end

  defp validate_historical_balance_selector(selector), do: {:ok, selector}

  def address_matches_regex?(%{address: address}, regex), do: String.match?(address, regex)

  def address_matches_regex?(%{addresses: addresses}, regex), do: Enum.all?(addresses, &String.match?(&1, regex))

  defp format_address(%{address: address}), do: address
  defp format_address(%{addresses: addresses}), do: Enum.join(addresses, ", ")
end
