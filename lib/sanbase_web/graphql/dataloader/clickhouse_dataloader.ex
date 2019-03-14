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
    |> Sanbase.Parallel.flat_pmap(fn organizations ->
      case Clickhouse.Github.total_dev_activity(organizations, from, to) do
        {:ok, dev_activity} ->
          dev_activity
          |> Enum.map(fn {organization, dev_activity} ->
            {organization, {:ok, dev_activity / days}}
          end)

        _ ->
          organizations
          |> Enum.map(fn organization ->
            {organization, {:nocache, {:ok, 0}}}
          end)
      end
    end)
    |> Map.new()
  end

  @doc ~s"""
  Returns a map with the ethereum spent by each project passed in `args`.
  The map key is the project's id.
  The map value is either `{:ok, value}` or `{:nocache, {:ok, value}}`.
  The :nocache value is returned if some problems were encountered while calculating the
  ethereum spent and the value won't be put in the cache.
  """
  def query(:eth_spent, args) do
    args = Enum.to_list(args)

    eth_spent =
      eth_addresses(args)
      |> Enum.chunk_every(10)
      |> Sanbase.Parallel.flat_pmap(&eth_spent(&1, args))
      |> Map.new()

    args
    |> Enum.map(fn %{project: project} ->
      {project.id, eth_spent_per_project(project, eth_spent)}
    end)
    |> Map.new()
  end

  # Calculate the ethereum spent for a single project by summing the ethereum
  # spent for each of its ethereum addresses. If an error is encountered while
  # calculating, the value will be wrapped in a :nocache tuple that the cache
  # knows how to handle
  defp eth_spent_per_project(project, eth_spent) do
    {:ok, addresses} = Project.eth_addresses(project)

    eth_spent_per_address =
      addresses
      |> Enum.map(fn address ->
        Map.get(eth_spent, address, {:ok, 0})
      end)

    project_eth_spent =
      for({:ok, value} <- eth_spent_per_address, do: value)
      |> Enum.sum()

    eth_spent_per_address
    |> Enum.any?(&match?({:error, _}, &1))
    |> result(project_eth_spent)
  end

  defp result(has_errors?, value)
  defp result(true, value), do: {:nocache, {:ok, value}}
  defp result(false, value), do: {:ok, value}

  defp eth_spent(eth_addresses, args) do
    [%{from: from, to: to} | _] = args

    case Clickhouse.EthTransfers.eth_spent(eth_addresses, from, to) do
      {:ok, eth_spent} ->
        eth_spent
        |> Enum.map(fn {addr, value} -> {addr, {:ok, value}} end)

      _ ->
        eth_addresses
        |> Enum.map(fn addr -> {addr, {:error, :novalue}} end)
    end
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
