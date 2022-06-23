defmodule SanbaseWeb.Graphql.ClickhouseDataloader do
  alias Sanbase.Clickhouse
  alias Sanbase.Model.Project
  alias Sanbase.Metric

  def data(), do: Dataloader.KV.new(&query/2)

  def query(:aggregated_metric, args) do
    args_list = args |> Enum.to_list()

    args_list
    |> Enum.group_by(fn %{selector: selector} -> selector end)
    |> Sanbase.Parallel.map(fn {selector, group} ->
      {metric, from, to, opts} = selector
      slugs = Enum.map(group, & &1.slug)

      data =
        case Metric.aggregated_timeseries_data(metric, %{slug: slugs}, from, to, opts) do
          {:ok, result} -> result
          {:error, error} -> {:error, error}
        end

      {selector, data}
    end)
    |> Map.new()
  end

  def query(:average_daily_active_addresses, args) do
    args
    |> Enum.to_list()
    |> Enum.group_by(fn %{from: from, to: to} -> {from, to} end)
    |> Sanbase.Parallel.map(fn {{from, to}, group} ->
      {{from, to}, average_daily_active_addresses(group, from, to)}
    end)
    |> Map.new()
  end

  # Returns a map with the average dev activity for every project passed in `args`.
  #
  # The map key is the `days` argument passed. This is done so aliases are
  # supported in the format:
  #   ```
  #   ...
  #   dev_7d: averageDevActivity(days: 7)
  #   dev_30d: averageDevActivity(days: 30)
  #   ...
  #   ```
  #
  # The `days` key points to a map of results or to an {:error, error} tuple.
  # The map of results has github organizations as key and their average activity
  # as value.
  def query(:average_dev_activity, args) do
    args = Enum.to_list(args)

    Enum.group_by(args, fn %{days: days} -> days end)
    |> Sanbase.Parallel.map(
      fn {days, group} ->
        {days, average_dev_activity(group, days)}
      end,
      ordered: false
    )
    |> Map.new()
  end

  # Returns a map with the ethereum spent by each project passed in `args`.
  # The map key is the project's id.
  # The map value is either `{:ok, value}` or `{:nocache, {:ok, value}}`.
  # The :nocache value is returned if some problems were encountered while calculating the
  # ethereum spent and the value won't be put in the cache.
  def query(:eth_spent, args) do
    args = Enum.to_list(args)

    Enum.group_by(args, fn %{days: days} -> days end)
    |> Sanbase.Parallel.map(
      fn {days, group} ->
        {days, eth_spent_for_days_group(group |> Enum.map(& &1.project), days)}
      end,
      ordered: false
    )
    |> Map.new()
  end

  defp average_daily_active_addresses(args, from, to) do
    slugs =
      args
      |> Enum.map(fn %{project: project} -> project.slug end)
      |> Enum.reject(&is_nil/1)

    Sanbase.Metric.aggregated_timeseries_data(
      "daily_active_addresses",
      %{slug: slugs},
      from,
      to,
      aggregation: :avg
    )
    |> case do
      {:ok, result} ->
        result

      {:error, error} ->
        {:error, error}
    end
  end

  defp average_dev_activity(group, days) do
    to = Timex.now()
    from = Timex.shift(to, days: -days)

    organizations =
      group
      |> Enum.flat_map(fn %{project: project} ->
        {:ok, organizations} = Project.github_organizations(project)
        organizations
      end)

    Sanbase.Metric.aggregated_timeseries_data(
      "dev_activity",
      %{organizations: organizations},
      from,
      to
    )
    |> case do
      {:ok, result} ->
        result
        |> Enum.into(%{}, fn {org, dev_activity} ->
          {org, dev_activity / days}
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  defp eth_spent_for_days_group(projects, days) do
    from = Timex.shift(Timex.now(), days: -days)
    to = Timex.now()

    eth_spent_per_address =
      eth_addresses(projects)
      |> Enum.chunk_every(25)
      |> Sanbase.Parallel.map(&eth_spent(&1, from, to),
        map_type: :flat_map,
        max_concurrency: 8,
        ordered: false
      )
      |> Map.new()

    projects
    |> Enum.map(fn project ->
      {project.id, eth_spent_per_project(project, eth_spent_per_address)}
    end)
    |> Map.new()
  end

  # Calculate the ethereum spent for a single project by summing the ethereum
  # spent for each of its ethereum addresses. If an error is encountered while
  # calculating, the value will be wrapped in a :nocache tuple that the cache
  # knows how to handle
  defp eth_spent_per_project(project, eth_spent_per_address) do
    {:ok, addresses} = Project.eth_addresses(project)

    project_addresses_eth_spent =
      addresses
      |> Enum.map(fn address ->
        Map.get(eth_spent_per_address, address, {:ok, 0})
      end)

    project_eth_spent =
      for({:ok, value} <- project_addresses_eth_spent, do: value)
      |> Enum.sum()

    project_addresses_eth_spent
    |> Enum.any?(&match?({:error, _}, &1))
    |> project_eth_spent_result(project_eth_spent)
  end

  defp project_eth_spent_result(has_errors?, value)
  defp project_eth_spent_result(true, value) when value < 0, do: {:nocache, {:ok, abs(value)}}
  defp project_eth_spent_result(true, _), do: {:nocache, {:ok, 0}}
  defp project_eth_spent_result(false, value) when value < 0, do: {:ok, abs(value)}
  defp project_eth_spent_result(false, _), do: {:ok, 0}

  defp eth_spent(eth_addresses, from, to) do
    case Clickhouse.HistoricalBalance.EthSpent.eth_balance_change(eth_addresses, from, to) do
      {:ok, balance_changes} ->
        balance_changes
        |> Enum.map(fn %{address: address, balance_change_amount: balance_change_amount} ->
          {address, {:ok, balance_change_amount}}
        end)

      {:error, _} ->
        eth_addresses
        |> Enum.map(fn addr -> {addr, {:error, :novalue}} end)
    end
  end

  defp eth_addresses(projects) do
    projects
    |> Enum.map(fn project ->
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
