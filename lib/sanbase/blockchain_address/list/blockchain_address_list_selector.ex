defmodule Sanbase.BlockchainAddress.ListSelector do
  @moduledoc false
  alias Sanbase.Clickhouse.Label
  alias Sanbase.Utils.ListSelector.Transform

  defdelegate valid_selector?(args), to: __MODULE__.Validator

  def addresses(%{selector: _selector} = args) do
    opts = args_to_opts(args)
    blockchain_addresses = get_blockchain_addresses(opts)

    {:ok,
     %{
       blockchain_addresses: blockchain_addresses,
       has_pagination?: Keyword.get(opts, :has_pagination?),
       all_included_blockchain_addresses: Keyword.get(opts, :included_blockchain_addresses)
     }}
  end

  defp get_blockchain_addresses(opts) do
    Sanbase.Utils.Transform.combine_mapsets(opts[:included_blockchain_addresses], combinator: opts[:filters_combinator])
  end

  def args_to_opts(args) do
    args = Sanbase.MapUtils.atomize_keys(args)

    filters = Transform.args_to_filters(args)
    filters_combinator = Transform.args_to_filters_combinator(args)

    included_blockchain_addresses = included_blockchain_addresses_by_filters(filters)

    [
      included_blockchain_addresses: included_blockchain_addresses,
      filters_combinator: filters_combinator
    ]
  end

  defp included_blockchain_addresses_by_filters([]), do: []

  defp included_blockchain_addresses_by_filters([_ | _] = filters) when is_list(filters) do
    Sanbase.Parallel.map(
      filters,
      fn filter ->
        cache_key = Sanbase.Cache.hash({__MODULE__, :included_blockchain_addresses_by_filter, filter})

        {:ok, blockchain_addresses} =
          Sanbase.Cache.get_or_store(cache_key, fn -> blockchain_addresses_by_filter(filter) end)

        MapSet.new(blockchain_addresses)
      end,
      timeout: 40_000,
      ordered: false,
      max_concurrency: 4
    )
  end

  defp blockchain_addresses_by_filter(%{name: "addresses_by_labels", args: args}) do
    label_fqns = args[:label_fqns]
    blockchain = args[:blockchain]

    combinator =
      (args[:labels_combinator] || "or") |> String.downcase() |> String.to_existing_atom()

    opts = [labels_combinator: combinator, blockchain: blockchain]

    Label.addresses_by_labels(label_fqns, opts)
  end

  defp blockchain_addresses_by_filter(%{name: "addresses_by_label_keys", args: args}) do
    label_keys = args[:label_keys]
    blockchain = args[:blockchain]

    opts = [blockchain: blockchain]

    Label.addresses_by_label_keys(label_keys, opts)
  end

  # Fetch the top addresses ordered by their balance in descendig order. If the
  # `labels` key is present in the args, only the addresses that have one of these labels
  # are returned.
  defp blockchain_addresses_by_filter(%{name: "top_addresses", args: args}) do
    opts = [
      page: args.page,
      page_size: args.page_size,
      direction: :desc,
      labels: args[:labels] || :all
    ]

    case Sanbase.Balance.current_balance_top_addresses(args.slug, opts) do
      {:ok, result} ->
        blockchain_addresses =
          Enum.map(result, fn %{address: _, infrastructure: _} = map ->
            Map.take(map, [:infrastructure, :address])
          end)

        {:ok, blockchain_addresses}

      {:error, error} ->
        {:error, error}
    end
  end
end
