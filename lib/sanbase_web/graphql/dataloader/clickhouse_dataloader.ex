defmodule SanbaseWeb.Graphql.ClickhouseDataloader do
  alias Sanbase.Clickhouse
  alias Sanbase.Model.Project

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:average_dev_activity, args) do
    args = Enum.to_list(args)
    [%{from: from, to: to, days: days} | _] = args

    args
    |> Enum.map(fn %{project: project} ->
      case Project.github_organization(project) do
        {:ok, organization} -> organization
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(100)
    |> Sanbase.Parallel.pmap_concurrent(
      fn organizations ->
        {:ok, dev_activity} = Clickhouse.Github.total_dev_activity(organizations, from, to)

        dev_activity
        |> Enum.map(fn {organization, dev_activity} -> {organization, dev_activity / days} end)
      end,
      map_type: :flat_map
    )
    |> Map.new()
  end

  def query(:eth_spent, args) do
    args = Enum.to_list(args)

    eth_spent =
      eth_addresses(args)
      |> Enum.chunk_every(10)
      |> Sanbase.Parallel.pmap_concurrent(&eth_spent(&1, args), map_type: :flat_map)
      |> Map.new()

    args
    |> Enum.map(fn %{project: project} ->
      {:ok, addresses} = Project.eth_addresses(project)

      eth_spent_per_project =
        addresses
        |> Enum.map(fn address ->
          Map.get(eth_spent, address, 0)
        end)
        |> Enum.sum()

      {project.id, eth_spent_per_project}
    end)
    |> Map.new()
  end

  defp eth_spent(eth_addresses, args) do
    [%{from: from, to: to} | _] = args
    {:ok, eth_spent} = Clickhouse.EthTransfers.eth_spent(eth_addresses, from, to)
    eth_spent
  end

  defp eth_addresses(args) do
    args
    |> Enum.map(fn %{project: project} ->
      case Project.eth_addresses(project) do
        {:ok, addresses} when addresses != [] ->
          addresses

        _ ->
          nil
      end
    end)
    |> Enum.reject(fn addresses -> addresses == nil or addresses == [] end)
  end
end
