defmodule SanbaseWeb.Graphql.BalanceDataloader do
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance

  def data(), do: Dataloader.KV.new(&query/2)

  def query(:current_address_slug_balance, address_slug_pairs) do
    slug_groups =
      Enum.group_by(
        address_slug_pairs,
        fn {_address, slug} -> slug end,
        fn {address, _slug} -> address end
      )

    Sanbase.Parallel.map(slug_groups, &get_balance/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  defp get_balance({slug, addresses}) do
    {:ok, infr} = Project.by_slug(slug) |> Project.infrastructure_real_code()

    case HistoricalBalance.current_balance(%{infrastructure: infr, slug: slug}, addresses) do
      {:ok, list} ->
        Enum.reduce(list, %{}, fn map, acc ->
          Map.put(acc, {map.address, slug}, map.balance)
        end)

      {:error, _error} ->
        %{}
    end
  end
end
