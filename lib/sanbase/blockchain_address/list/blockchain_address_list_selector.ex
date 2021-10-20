defmodule Sanbase.BlockchainAddress.ListSelector do
  alias Sanbase.Utils.ListSelector.Transform

  defdelegate valid_selector?(args), to: __MODULE__.Validator

  def addresses(%{selector: selector} = args) do
    opts = args_to_opts(args)
    blockchain_addresses = evaluate_selector(opts)

    {:ok,
     %{
       blockchain_addresses: blockchain_addresses,
       has_pagination?: Keyword.get(opts, :has_pagination?),
       all_included_blockchain_addresses: Keyword.get(opts, :included_blockchain_addresses)
     }}
  end

  defp evaluate_selector(%{name: "top_addresses", args: %{slug: slug, limit: limit}}) do
    Sanbase.Balance.current_balance_top_addresses(slug, 1, limit, :desc)
  end

  defp evaluate_selector(selector) do
    {:error, "Invalid selector: #{inspect(selector)}"}
  end

  def args_to_opts(args) do
    args = Sanbase.MapUtils.atomize_keys(args)

    filters = Transform.args_to_filters(args)
    order_by = Transform.args_to_order_by(args)
    pagination = Transform.args_to_pagination(args)
    filters_combinator = Transform.args_to_filters_combinator(args)

    included_blockchain_addresses =
      filters
      |> included_blockchain_addresses_by_filters(filters_combinator)

    # ordered_blockchain_address =
    #   order_by |> ordered_blockchain_address_by_order_by(included_blockchain_addresses)

    [
      has_selector?: not is_nil(args[:selector]),
      has_order?: not is_nil(order_by),
      has_pagination?: not is_nil(pagination),
      pagination: pagination,
      included_blockchain_addresses: included_blockchain_addresses
      # ordered_blockchain_addresss: ordered_blockchain_addresss
    ]
  end

  defp included_blockchain_addresses_by_filters([], _), do: []

  defp included_blockchain_addresses_by_filters([_ | _] = filters, filters_combinator)
       when is_list(filters) do
    slug_mapsets =
      filters
      |> Sanbase.Parallel.map(
        fn filter ->
          cache_key =
            {__MODULE__, :included_blockchain_addresses_by_filter, filter} |> Sanbase.Cache.hash()

          {:ok, blockchain_addresses} =
            Sanbase.Cache.get_or_store(cache_key, fn -> blockchain_addresses_by_filter(filter) end)

          blockchain_addresses |> MapSet.new()
        end,
        timeout: 40_000,
        ordered: false,
        max_concurrency: 4
      )

    case filters_combinator do
      "and" ->
        slug_mapsets
        |> Enum.reduce(&MapSet.intersection(&1, &2))
        |> Enum.to_list()

      "or" ->
        slug_mapsets
        |> Enum.reduce(&MapSet.union(&1, &2))
        |> Enum.to_list()
    end
  end

  defp blockchain_addresses_by_filter(%{name: "top_addresses", args: %{}}) do
    {:ok, []}
  end
end
