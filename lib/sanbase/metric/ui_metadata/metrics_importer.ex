defmodule Sanbase.Metric.UIMetadata.MetricsImporter do
  @moduledoc """
  Module for importing metrics metadata from JSON files.

  This module handles the entire process of importing metrics data from a JSON file,
  including creating necessary categories and groups, and reporting success/failure statistics.
  """

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Metric.UIMetadata.Category
  alias Sanbase.Metric.UIMetadata.Group
  alias Sanbase.Metric.UIMetadata.DisplayOrder

  @doc """
  Import metrics, categories, and groups from a JSON file.

  Returns {:ok, %{inserted: count, failed: failed_count, failed_metrics: failed_metrics_list}} on success
  or {:error, reason} on failure.

  ## Examples

      iex> MetricsImporter.import_from_file("metrics_data.json")
      {:ok, %{inserted: 42, failed: 2, failed_metrics: [...]}}

  """
  def import_from_file(file_path \\ "ui_metrics_metadata.json") do
    with {:ok, json_data} <- File.read(file_path),
         {:ok, data} <- Jason.decode(json_data),
         dupes = find_duplicate_metrics(data),
         _ = log_duplicates(dupes),
         {:ok, stats} <- process_import_data(data) do
      {:ok, Map.put(stats, :duplicates, dupes)}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Failed to import: #{inspect(reason)}"}
    end
  end

  defp process_import_data(data) do
    Repo.transaction(fn ->
      categories = data["categories"]
      categories_map = create_categories(categories)
      metrics_by_category = data["metrics"]

      # Use a MapSet to track metrics we've already processed
      metrics_by_category
      |> import_metrics_by_category(categories_map, MapSet.new())
      |> format_import_stats()
    end)
  end

  defp import_metrics_by_category(metrics_by_category, categories_map, processed_metrics) do
    metrics_by_category
    |> Enum.reduce({0, 0, [], processed_metrics}, fn {category_name, metrics},
                                                     {inserted_count, existing_count,
                                                      failed_metrics, processed} ->
      category_id = Map.get(categories_map, category_name)

      if category_id do
        import_metrics_for_category(
          metrics,
          category_id,
          category_name,
          inserted_count,
          existing_count,
          failed_metrics,
          processed
        )
      else
        # Category not found, mark all metrics as failed
        new_failed = mark_metrics_as_failed(metrics, category_name, "Category not found")
        {inserted_count, existing_count, failed_metrics ++ new_failed, processed}
      end
    end)
  end

  defp mark_metrics_as_failed(metrics, category_name, reason) do
    Enum.map(metrics, fn metric_data ->
      %{
        metric: metric_data["metric"],
        category: category_name,
        group: metric_data["group"],
        reason: reason
      }
    end)
  end

  defp import_metrics_for_category(
         metrics,
         category_id,
         category_name,
         inserted_count,
         existing_count,
         failed_metrics,
         processed_metrics
       ) do
    # Extract unique groups from this category's metrics
    groups = extract_unique_groups(metrics)

    # Create groups and get a map of group_name => group_id
    groups_map = create_groups(groups, category_id)

    # Process each metric
    Enum.reduce(
      metrics,
      {inserted_count, existing_count, failed_metrics, processed_metrics},
      fn metric_data, {inserted, existing, failed, processed} ->
        process_single_metric(
          metric_data,
          category_id,
          category_name,
          groups_map,
          inserted,
          existing,
          failed,
          processed
        )
      end
    )
  end

  defp extract_unique_groups(metrics) do
    metrics
    |> Enum.map(fn metric -> Map.get(metric, "group") end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn group -> group == "" end)
    |> Enum.uniq()
  end

  defp process_single_metric(
         metric_data,
         category_id,
         category_name,
         groups_map,
         inserted_count,
         existing_count,
         failed,
         processed_metrics
       ) do
    group_name = Map.get(metric_data, "group")
    group_id = if group_name && group_name != "", do: Map.get(groups_map, group_name), else: nil

    # Get metric name and registry_metric (template) if present
    metric_name = metric_data["metric"]
    registry_metric = metric_data["registry_metric"]

    updated_processed = MapSet.put(processed_metrics, metric_name)

    # Add the metric
    result =
      DisplayOrder.add_metric(
        metric_name,
        category_id,
        group_id,
        ui_human_readable_name: metric_data["label"] || metric_name,
        chart_style: metric_data["style"] || "line",
        unit: metric_data["format"] || "",
        description: metric_data["description"] || "",
        args: metric_data["args"] || %{},
        registry_metric: registry_metric
      )

    case result do
      {:ok, _} ->
        Logger.info("Successfully inserted new metric: #{metric_name}")
        {inserted_count + 1, existing_count, failed, updated_processed}

      {:exists, _} ->
        Logger.info("Metric #{metric_name} already exists in database")
        # Count as existing, not as new insertion
        {inserted_count, existing_count + 1, failed, updated_processed}

      {:error, reason} ->
        error_entry = %{
          metric: metric_name,
          category: category_name,
          group: group_name,
          reason: inspect(reason)
        }

        Logger.error("Failed to insert metric #{metric_name}: #{inspect(reason)}")
        {inserted_count, existing_count, [error_entry | failed], updated_processed}
    end
  end

  defp format_import_stats({inserted_count, existing_count, failed_metrics, _processed_metrics}) do
    %{
      inserted: inserted_count,
      existing: existing_count,
      total_processed: inserted_count + existing_count + length(failed_metrics),
      failed: length(failed_metrics),
      failed_metrics: failed_metrics
    }
  end

  defp create_categories(categories) do
    Enum.reduce(categories, %{}, fn category_name, acc ->
      # Set a default display_order based on the index in the original list
      display_order = Enum.find_index(categories, fn cat -> cat == category_name end) || 0

      case Category.by_name(category_name) do
        nil ->
          # Create new category
          case Category.create(%{name: category_name, display_order: display_order}) do
            {:ok, category} ->
              Map.put(acc, category_name, category.id)

            {:error, _} ->
              acc
          end

        existing ->
          # Use existing category
          Map.put(acc, category_name, existing.id)
      end
    end)
  end

  defp create_groups(groups, category_id) do
    Enum.reduce(groups, %{}, fn group_name, acc ->
      case Group.create_if_not_exists(group_name, category_id) do
        {:ok, group} ->
          Map.put(acc, group_name, group.id)

        {:error, _} ->
          acc
      end
    end)
  end

  # Find duplicate metrics in the JSON file
  defp find_duplicate_metrics(data) do
    metrics_by_category = data["metrics"]

    # Flatten metrics from all categories into a list
    all_metrics =
      metrics_by_category
      |> Enum.flat_map(fn {category, metrics} ->
        Enum.map(metrics, fn metric ->
          %{
            metric: metric["metric"],
            category: category,
            group: metric["group"]
          }
        end)
      end)

    # Group by metric name
    grouped = Enum.group_by(all_metrics, fn %{metric: m} -> m end)

    # Keep only metrics that appear more than once
    duplicates =
      grouped
      |> Enum.filter(fn {_key, values} -> length(values) > 1 end)
      |> Map.new()

    duplicates
  end

  # Log duplicates
  defp log_duplicates(dupes) do
    if map_size(dupes) > 0 do
      Logger.warn("Found #{map_size(dupes)} duplicate metrics in JSON file:")

      Enum.each(dupes, fn {metric_name, occurrences} ->
        locations =
          Enum.map_join(occurrences, ", ", fn %{category: c, group: g} ->
            "#{c}/#{g || "no group"}"
          end)

        Logger.warn("  - #{metric_name} appears in: #{locations}")
      end)
    end

    dupes
  end

  @doc """
  Get a list of duplicate metrics found in the JSON file.

  Returns a map where keys are metric names and values are lists of locations
  (with category and group) where the metric appears.

  ## Examples

      iex> MetricsImporter.get_duplicate_metrics("metrics_data.json")
      %{
        "daily_active_addresses" => [
          %{category: "On-chain", group: "Network Activity"},
          %{category: "On-chain", group: "User Activity"}
        ]
      }
  """
  def get_duplicate_metrics(file_path \\ "ui_metrics_metadata.json") do
    with {:ok, json_data} <- File.read(file_path),
         {:ok, data} <- Jason.decode(json_data) do
      find_duplicate_metrics(data)
    else
      {:error, reason} ->
        Logger.error("Failed to read or parse JSON file: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Print a list of duplicate metrics found in the JSON file to the console.
  Useful for debugging and reviewing the data.

  ## Examples

      iex> MetricsImporter.print_duplicates("metrics_data.json")
      Found 3 duplicate metrics in metrics_data.json:
      - daily_active_addresses appears in:
        * On-chain/Network Activity
        * On-chain/User Activity
      - price_usd appears in:
        * Financial/Price
        * Financial/Market
      - github_activity appears in:
        * Development/GitHub
        * Development/Activity
      :ok
  """
  def print_duplicates(file_path \\ "ui_metrics_metadata.json") do
    duplicates = get_duplicate_metrics(file_path)

    if map_size(duplicates) > 0 do
      IO.puts("Found #{map_size(duplicates)} duplicate metrics in #{file_path}:")

      duplicates
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.each(fn {metric_name, occurrences} ->
        IO.puts("- #{metric_name} appears in:")

        Enum.each(occurrences, fn %{category: category, group: group} ->
          IO.puts("  * #{category}/#{group || "no group"}")
        end)
      end)
    else
      IO.puts("No duplicate metrics found in #{file_path}")
    end

    :ok
  end
end
