defmodule Sanbase.Metric.Category.Scripts.CopyCategories do
  @moduledoc """
  Scripts for importing metric categories and groups from production.
  """

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricGroup
  alias Sanbase.Repo

  @graphql_query """
  {
    getOrderedMetrics {
      categories
      metrics {
        args
        categoryName
        chartStyle
        description
        displayOrder
        groupName
        uiHumanReadableName
        type
        uiKey
        unit
      }
    }
  }
  """

  def run() do
    env = Application.get_env(:sanbase, :env)
    deployment_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)

    case {env, deployment_env} do
      {:dev, _} ->
        do_run("https://api.santiment.net/graphql")

      {:prod, "stage"} ->
        do_run("https://api-stage.santiment.net/graphql")

      {:prod, "prod"} ->
        do_run("https://api.santiment.net/graphql")

      _ ->
        raise(
          ArgumentError,
          "Cannot run CopyCategories in env #{env} and deployment_env #{deployment_env}."
        )
    end
  end

  def do_run(api_url) do
    with {:ok, data} <- fetch_ordered_metrics(api_url),
         {:ok, _result} <- import_categories_and_groups(data),
         {:ok, _result} <- assign_metrics_to_categoreis(data) do
      :ok
    end
  end

  defp assign_metrics_to_categories(%{"metrics" => metrics}) do
    Enum.reduce(metrics, %{}, fn map, acc ->
      %{
        "categoryName" => category,
        "groupName" => group,
        "displayOrder" => display_order,
        "metric" => metric
      }
    end)
  end

  defp fetch_ordered_metrics(api_url) do
    IO.puts("🔍 Fetching ordered metrics from #{api_url}...")

    request_body = Jason.encode!(%{query: @graphql_query})

    case Req.post(api_url,
           body: request_body,
           headers: [{"content-type", "application/json"}]
         ) do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"data" => %{"getOrderedMetrics" => data}} ->
            {:ok, data}

          %{"errors" => errors} ->
            {:error, {:graphql_errors, errors}}

          _ ->
            {:error, {:unexpected_response, body}}
        end

      {:ok, response} ->
        {:error, {:http_error, response.status, response.body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp import_categories_and_groups(%{"categories" => categories, "metrics" => metrics}) do
    IO.puts("\n📊 Processing #{length(categories)} categories and #{length(metrics)} metrics...")

    category_groups =
      metrics
      |> extract_category_groups()
      |> Enum.sort_by(& &1.display_order)

    result = create_categories_and_groups(category_groups)
    print_result(result)
  end

  defp extract_category_groups(metrics) do
    metrics
    |> Enum.group_by(& &1["categoryName"])
    |> Enum.map(&build_category_structure/1)
  end

  defp build_category_structure({category_name, category_metrics}) do
    groups = extract_groups(category_metrics)
    category_display_order = min_display_order(category_metrics)

    %{
      name: category_name,
      display_order: category_display_order,
      groups: groups
    }
  end

  defp extract_groups(category_metrics) do
    category_metrics
    |> Enum.group_by(& &1["groupName"])
    |> Enum.reject(fn {group_name, _} -> is_nil(group_name) or group_name == "" end)
    |> Enum.map(&build_group_structure/1)
    |> Enum.sort_by(& &1.display_order)
  end

  defp build_group_structure({group_name, group_metrics}) do
    %{name: group_name, display_order: min_display_order(group_metrics)}
  end

  defp min_display_order(metrics) do
    metrics |> Enum.map(& &1["displayOrder"]) |> Enum.min()
  end

  defp create_categories_and_groups(category_groups) do
    Repo.transaction(fn ->
      Enum.reduce(category_groups, %{categories: [], groups: []}, &process_category/2)
    end)
  end

  defp process_category(category_data, acc) do
    category = create_or_update_category(category_data)

    groups =
      Enum.map(category_data.groups, fn group_data ->
        create_or_update_group(group_data, category.id)
      end)

    %{
      categories: [category | acc.categories],
      groups: groups ++ acc.groups
    }
  end

  defp print_result({:ok, %{categories: categories, groups: groups}}) do
    IO.puts("\n✅ Successfully created/updated:")
    IO.puts("   - #{length(categories)} categories")
    IO.puts("   - #{length(groups)} groups")

    {:ok, %{categories: Enum.reverse(categories), groups: Enum.reverse(groups)}}
  end

  defp print_result({:error, reason}) do
    IO.puts("\n❌ Transaction failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp create_or_update_category(%{name: name, display_order: display_order}) do
    case MetricCategory.get_by_name(name) do
      nil ->
        {:ok, category} =
          MetricCategory.create(%{
            name: name,
            display_order: display_order
          })

        IO.puts("  ✨ Created category: #{name} (order: #{display_order})")
        category

      existing_category ->
        {:ok, category} =
          MetricCategory.update(existing_category, %{
            display_order: display_order
          })

        IO.puts("  🔄 Updated category: #{name} (order: #{display_order})")
        category
    end
  end

  defp create_or_update_group(%{name: name, display_order: display_order}, category_id) do
    case MetricGroup.get_by_name_and_category(name, category_id) do
      nil ->
        {:ok, group} =
          MetricGroup.create(%{
            name: name,
            display_order: display_order,
            category_id: category_id
          })

        IO.puts("    ✨ Created group: #{name} (order: #{display_order})")
        group

      existing_group ->
        {:ok, group} =
          MetricGroup.update(existing_group, %{
            display_order: display_order
          })

        IO.puts("    🔄 Updated group: #{name} (order: #{display_order})")
        group
    end
  end
end
