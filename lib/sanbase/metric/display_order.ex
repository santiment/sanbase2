defmodule Sanbase.Metric.DisplayOrder do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry

  # Define a parser for CSV files
  NimbleCSV.define(MetricsCSVParser, separator: ",", escape: "\"")

  @type t :: %__MODULE__{
          id: integer(),
          metric: String.t(),
          category: String.t(),
          group: String.t(),
          display_order: integer(),
          source_type: String.t(),
          source_id: integer(),
          added_at: DateTime.t(),
          label: String.t(),
          style: String.t(),
          format: String.t(),
          description: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_display_order" do
    field(:metric, :string)
    field(:category, :string)
    field(:group, :string, default: "")
    field(:display_order, :integer)
    field(:source_type, :string, default: "code")
    field(:source_id, :integer)
    field(:added_at, :utc_datetime)
    field(:label, :string)
    field(:style, :string, default: "line")
    field(:format, :string, default: "")
    field(:description, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = display_order, attrs) do
    display_order
    |> cast(attrs, [
      :metric,
      :category,
      :group,
      :display_order,
      :source_type,
      :source_id,
      :added_at,
      :label,
      :style,
      :format,
      :description
    ])
    |> validate_required([:metric, :category, :display_order])
    |> validate_inclusion(:source_type, ["registry", "code"])
    |> unique_constraint(:metric)
  end

  @doc """
  Create a new metric display order entry.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a metric display order entry.
  """
  def update(%__MODULE__{} = display_order, attrs) do
    display_order
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a metric display order entry.
  """
  def delete(%__MODULE__{} = display_order) do
    Repo.delete(display_order)
  end

  @doc """
  Get a metric display order entry by metric name.
  """
  def by_metric(metric) do
    Repo.get_by(__MODULE__, metric: metric)
  end

  @doc """
  Get all metric display order entries.
  """
  def all do
    Repo.all(__MODULE__)
  end

  @doc """
  Get all metric display order entries ordered by category, group, and display_order.
  """
  def all_ordered do
    # First get the minimum display_order for each category to determine category order
    category_orders =
      Repo.all(
        from(m in __MODULE__,
          group_by: m.category,
          select: {m.category, min(m.display_order)}
        )
      )
      |> Map.new()

    # Then get all metrics and sort them by category order, then group, then display_order
    metrics = Repo.all(__MODULE__)

    Enum.sort_by(metrics, fn metric ->
      category_order = Map.get(category_orders, metric.category, 999)
      {category_order, metric.group, metric.display_order}
    end)
  end

  @doc """
  Get all metric display order entries for a specific category.
  """
  def by_category(category) do
    query =
      from(m in __MODULE__,
        where: m.category == ^category,
        order_by: [asc: m.group, asc: m.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Get all metric display order entries for a specific category and group.
  """
  def by_category_and_group(category, group) do
    query =
      from(m in __MODULE__,
        where: m.category == ^category and m.group == ^group,
        order_by: [asc: m.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Get all metrics that were added in the last n days.
  """
  def recently_added(days \\ 14) do
    date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from(m in __MODULE__,
        where: m.added_at > ^date,
        order_by: [asc: m.category, asc: m.group, asc: m.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Reorder metrics within a category and group.
  The new_order parameter should be a list of maps with metric and display_order keys.
  """
  def reorder_metrics(category, new_order) do
    Repo.transaction(fn ->
      # Process each metric in the new order
      Enum.each(new_order, fn %{metric: metric, display_order: new_display_order} ->
        # Find the metric in the database
        case Repo.get_by(__MODULE__, metric: metric) do
          nil ->
            Repo.rollback("Metric #{metric} not found")

          %__MODULE__{} = record ->
            # Check if the metric is in the correct category
            if record.category != category do
              Repo.rollback("Metric #{metric} is not in category #{category}")
            else
              # Update the display order
              changeset = changeset(record, %{display_order: new_display_order})

              case Repo.update(changeset) do
                {:ok, _} -> :ok
                {:error, error} -> Repo.rollback(error)
              end
            end
        end
      end)

      :ok
    end)
  end

  @doc """
  Import metrics from a CSV file.
  The CSV file should have the following columns:
  metric,label,category,group,style,format,description

  This will preserve the order of categories, groups, and metrics as they appear in the CSV file.

  Returns {:ok, [{:added, metric} | {:updated, metric}]} on success or {:error, [error_messages]} on failure.
  """
  def import_from_csv(file_path) do
    # Read the CSV file line by line
    {:ok, file} = File.open(file_path, [:read])

    # Skip header row
    IO.read(file, :line)

    # Track categories, groups, and their order
    _category_order = %{}
    _group_order = %{}
    _metric_order = %{}

    # First pass: collect all categories, groups, and metrics to determine their order
    {category_order, group_order, metric_order} =
      Stream.unfold(file, fn file ->
        case IO.read(file, :line) do
          :eof -> nil
          line -> {line, file}
        end
      end)
      |> Stream.map(&String.trim/1)
      |> Stream.filter(fn line -> line != "" end)
      |> Enum.reduce({%{}, %{}, %{}}, fn line, {cat_order, grp_order, met_order} ->
        fields = parse_csv_line(line)

        case fields do
          [metric, _label, category, group, _style, _format, _description]
          when length(fields) >= 7 ->
            # Add category to order map if not present
            cat_order =
              if Map.has_key?(cat_order, category) do
                cat_order
              else
                Map.put(cat_order, category, map_size(cat_order) + 1)
              end

            # Create a unique key for the category+group combination
            group_key = "#{category}:#{group || ""}"

            grp_order =
              if Map.has_key?(grp_order, group_key) do
                grp_order
              else
                Map.put(grp_order, group_key, map_size(grp_order) + 1)
              end

            # Add metric to order map
            met_order = Map.put(met_order, metric, map_size(met_order) + 1)

            {cat_order, grp_order, met_order}

          _ ->
            {cat_order, grp_order, met_order}
        end
      end)

    # Reset file position
    File.close(file)
    {:ok, file} = File.open(file_path, [:read])
    # Skip header again
    IO.read(file, :line)

    # Second pass: process each line with the collected order information
    result =
      Stream.unfold(file, fn file ->
        case IO.read(file, :line) do
          :eof -> nil
          line -> {line, file}
        end
      end)
      |> Stream.map(&String.trim/1)
      |> Stream.filter(fn line -> line != "" end)
      |> Enum.reduce({:ok, []}, fn line, {:ok, acc} ->
        # Parse the CSV line with proper handling of quoted fields
        fields = parse_csv_line(line)

        case process_csv_row(fields, category_order, group_order, metric_order) do
          {:ok, action_and_metric} -> {:ok, [action_and_metric | acc]}
          {:error, reason} -> {:error, [reason | acc]}
        end
      end)

    File.close(file)
    result
  end

  # Process a CSV row with order information
  defp process_csv_row(
         [metric, label, category, group, style, format, description],
         category_order,
         group_order,
         metric_order
       ) do
    # Check if the metric already exists in the display order
    case by_metric(metric) do
      nil ->
        # Get the order values from the maps
        _category_display_order = Map.get(category_order, category, 999)
        group_key = "#{category}:#{group || ""}"
        _group_display_order = Map.get(group_order, group_key, 999)
        metric_display_order = Map.get(metric_order, metric, 999)

        # Determine source type and source id
        {source_type, source_id} = determine_metric_source(metric)

        # Create a new display order entry
        attrs = %{
          metric: metric,
          category: category,
          group: group || "",
          display_order: metric_display_order,
          source_type: source_type,
          source_id: source_id,
          added_at: DateTime.utc_now(),
          label: label,
          style: style || "line",
          format: format || "",
          description: description || ""
        }

        case create(attrs) do
          {:ok, created} -> {:ok, {:added, created.metric}}
          {:error, error} -> {:error, "Failed to create metric #{metric}: #{inspect(error)}"}
        end

      existing ->
        # Update existing metric with new order and possibly category/group
        metric_display_order = Map.get(metric_order, metric, existing.display_order)

        # Determine source type and source id if not already set
        {source_type, source_id} =
          if is_nil(existing.source_type) do
            determine_metric_source(metric)
          else
            {existing.source_type, existing.source_id}
          end

        # Check if we need to update the metric
        if existing.display_order != metric_display_order ||
             existing.category != category ||
             existing.group != (group || "") ||
             existing.label != label ||
             existing.style != (style || "line") ||
             existing.format != (format || "") ||
             existing.description != (description || "") ||
             existing.source_type != source_type ||
             existing.source_id != source_id do
          # Use changeset to update the metric
          case existing
               |> changeset(%{
                 display_order: metric_display_order,
                 category: category,
                 group: group || "",
                 label: label,
                 style: style || "line",
                 format: format || "",
                 description: description || "",
                 source_type: source_type,
                 source_id: source_id
               })
               |> Repo.update() do
            {:ok, _updated} -> {:ok, {:updated, existing.metric}}
            {:error, error} -> {:error, "Failed to update metric #{metric}: #{inspect(error)}"}
          end
        else
          {:ok, {:unchanged, existing.metric}}
        end
    end
  end

  defp process_csv_row(row, _category_order, _group_order, _metric_order) do
    {:error, "Invalid row format: #{inspect(row)}"}
  end

  @doc """
  Synchronize metadata from a CSV file to the metric registry.
  This will update the metadata fields in the metric registry for registered metrics.
  """
  def sync_metadata_from_csv(file_path) do
    # Read the CSV file
    rows =
      file_path
      |> File.stream!()
      |> MetricsCSVParser.parse_stream()
      # Skip header row
      |> Stream.drop(1)
      |> Enum.to_list()

    # Process each row
    Enum.reduce(rows, {:ok, []}, fn row, {:ok, acc} ->
      case sync_metadata_from_row(row) do
        {:ok, _} -> {:ok, acc}
        {:error, reason} -> {:error, [reason | acc]}
      end
    end)
  end

  @doc """
  Get the ordered list of all metrics with their metadata.
  This combines data from both the metric registry and the display order table.
  """
  def get_ordered_metrics do
    # Get all metrics from the display order table
    ordered_metrics = all_ordered()

    # Get unique categories and their display order
    categories_with_order =
      Repo.all(
        from(m in __MODULE__,
          group_by: m.category,
          select: {m.category, min(m.display_order)},
          order_by: [asc: min(m.display_order)]
        )
      )

    # Extract just the categories in the correct order
    categories_in_order = Enum.map(categories_with_order, fn {category, _} -> category end)

    # Create a map of metric names to their registry entries
    registry_metrics =
      Registry.all()
      |> Registry.resolve()
      |> Enum.reduce(%{}, fn registry, acc ->
        Map.put(acc, registry.metric, registry)
      end)

    # Combine the data
    metrics =
      Enum.map(ordered_metrics, fn display_order ->
        metric = display_order.metric

        # Try to get the metric from the registry
        registry_metric = Map.get(registry_metrics, metric)

        # Get the added_at timestamp
        added_at = display_order.added_at || nil

        # Create the metric map with metadata from display_order
        %{
          metric: metric,
          label: get_preferred_value(registry_metric, :label, display_order.label),
          category: get_preferred_value(registry_metric, :category, display_order.category),
          group: get_preferred_value(registry_metric, :group, display_order.group),
          style: get_preferred_value(registry_metric, :style, display_order.style || "line"),
          format: get_preferred_value(registry_metric, :format, display_order.format || ""),
          description:
            get_preferred_value(registry_metric, :description, display_order.description || ""),
          source_type: display_order.source_type,
          source_id: display_order.source_id,
          added_at: added_at,
          is_new: is_new?(added_at),
          display_order: display_order.display_order
        }
      end)

    # Return both the metrics and the ordered categories
    %{
      metrics: metrics,
      categories: categories_in_order
    }
  end

  @doc """
  Add a single metric to the display order table.
  This will assign a unique display_order value that is higher than any existing value.
  """
  def add_metric(metric_name, category, group \\ "", opts \\ []) do
    label = Keyword.get(opts, :label, metric_name)
    style = Keyword.get(opts, :style, "line")
    format = Keyword.get(opts, :format, "")
    description = Keyword.get(opts, :description, "")
    source_type = Keyword.get(opts, :source_type)
    source_id = Keyword.get(opts, :source_id)

    # Check if the metric already exists
    case by_metric(metric_name) do
      nil ->
        # Get the highest display_order currently in use
        max_display_order =
          case Repo.one(from(m in __MODULE__, select: max(m.display_order))) do
            nil -> 0
            max -> max
          end

        # Determine source type and source id if not provided
        {source_type, source_id} =
          if source_type do
            {source_type, source_id}
          else
            determine_metric_source(metric_name)
          end

        # Create a new display order entry with a unique display_order
        attrs = %{
          metric: metric_name,
          category: category,
          group: group,
          display_order: max_display_order + 1,
          source_type: source_type,
          source_id: source_id,
          added_at: DateTime.utc_now(),
          label: label,
          style: style,
          format: format,
          description: description
        }

        create(attrs)

      existing ->
        # Return the existing entry
        {:ok, existing}
    end
  end

  @doc """
  Update the categories and groups of existing metrics in the display order table
  based on their values in the registry.
  """
  def update_categories_from_registry() do
    # Get all metrics from the registry
    registry_metrics =
      Registry.all()
      |> Registry.resolve()
      |> Enum.reduce(%{}, fn registry, acc ->
        Map.put(acc, registry.metric, registry)
      end)

    # Get all metrics from the display order table
    all_ordered = all_ordered()

    # Get the highest display_order currently in use
    max_display_order =
      case Repo.one(from(m in __MODULE__, select: max(m.display_order))) do
        nil -> 0
        max -> max
      end

    # Update each metric's category and group
    {_, _updated_metrics} =
      Enum.reduce(all_ordered, {max_display_order, []}, fn display_order,
                                                           {current_max, updated} ->
        case Map.get(registry_metrics, display_order.metric) do
          nil ->
            # Metric not in registry, skip
            {current_max, updated}

          _registry_metric ->
            # Try to get the category and group from the metric adapter
            new_category_and_group =
              case get_metric_adapter_metadata(display_order.metric) do
                {:ok, metadata} ->
                  # Get the category and group from the metadata
                  {metadata[:category] || "Uncategorized", metadata[:group] || ""}

                _ ->
                  # Fallback to existing display_order values
                  {display_order.category, display_order.group}
              end

            {new_category, new_group} = new_category_and_group

            # Update if different
            if display_order.category != new_category || display_order.group != new_group do
              # If category changed, we need a new display_order to maintain proper ordering
              new_max_order =
                if display_order.category != new_category,
                  do: current_max + 1,
                  else: display_order.display_order

              attrs = %{
                category: new_category,
                group: new_group,
                display_order: new_max_order
              }

              case display_order |> changeset(attrs) |> Repo.update() do
                {:ok, _} -> {max(current_max, new_max_order), [display_order.metric | updated]}
                {:error, _} -> {current_max, updated}
              end
            else
              {current_max, updated}
            end
        end
      end)

    :ok
  end

  @doc """
  Update the metrics registry from a CSV file.
  This will update the metadata fields in the metric registry for existing metrics.
  The CSV file should have the following columns:
  metric,label,category,group,style,format,description

  Returns a tuple with the count of metrics updated and a list of metrics that couldn't be updated.
  """
  def update_registry_from_csv(file_path) do
    # Read the CSV file line by line
    {:ok, file} = File.open(file_path, [:read])

    # Skip header row
    IO.read(file, :line)

    # Process each line
    result =
      Stream.unfold(file, fn file ->
        case IO.read(file, :line) do
          :eof -> nil
          line -> {line, file}
        end
      end)
      |> Stream.map(&String.trim/1)
      |> Stream.filter(fn line -> line != "" end)
      |> Enum.reduce({0, []}, fn line, {updated_count, errors} ->
        # Parse the CSV line with proper handling of quoted fields
        fields = parse_csv_line(line)

        case update_registry_from_row(fields) do
          {:ok, _} -> {updated_count + 1, errors}
          {:error, reason} -> {updated_count, [reason | errors]}
        end
      end)

    File.close(file)
    result
  end

  # Update registry from a CSV row
  defp update_registry_from_row([metric, label, category, group, style, format, description]) do
    # Try to find the metric in the registry
    case Registry.by_name(metric) do
      {:ok, registry} ->
        # Update the metadata fields
        attrs = %{
          label: label,
          category: category,
          group: group || "",
          style: style || "line",
          format: format || "",
          description: description || ""
        }

        Registry.update(registry, attrs) |> dbg()

      {:error, reason} ->
        # Metric not in registry
        {:error, "Metric #{metric} not found in registry: #{reason}"}
    end
  end

  defp update_registry_from_row(row) do
    {:error, "Invalid row format: #{inspect(row)}"}
  end

  # Private functions

  defp parse_csv_line(line) do
    # State machine for parsing CSV
    {fields, current_field, _in_quotes, _i} =
      String.to_charlist(line)
      |> Enum.reduce({[], "", false, 0}, fn char, {fields, current, in_quotes, index} ->
        cond do
          # Handle escaped quote inside quoted field
          char == ?" and in_quotes and String.at(line, index + 1) == "\"" ->
            {fields, current <> "\"", in_quotes, index + 1}

          # Start or end of quoted field
          char == ?" ->
            {fields, current, !in_quotes, index}

          # Field separator outside quotes
          char == ?, and not in_quotes ->
            {fields ++ [current], "", in_quotes, index}

          # Regular character
          true ->
            {fields, current <> <<char::utf8>>, in_quotes, index}
        end
      end)

    # Add the last field
    fields ++ [current_field]
  end

  defp sync_metadata_from_row([metric, label, category, group, style, format, description]) do
    # Try to find the metric in the registry
    case Registry.by_name(metric) do
      {:ok, registry} ->
        # Update the metadata fields
        attrs = %{
          label: label,
          category: category,
          group: group || "",
          style: style || "line",
          format: format || "",
          description: description || ""
        }

        # Update the registry
        registry_result = Registry.update(registry, attrs, emit_event: false)

        # Also update the display order entry if it exists
        case by_metric(metric) do
          nil ->
            # Create a new display order entry if it doesn't exist
            add_metric(metric, category, group || "",
              label: label,
              style: style || "line",
              format: format || "",
              description: description || "",
              source_type: "registry",
              source_id: registry.id
            )

          display_order ->
            # Update the existing display order entry
            __MODULE__.update(display_order, %{
              category: category,
              group: group || "",
              label: label,
              style: style || "line",
              format: format || "",
              description: description || "",
              source_type: "registry",
              source_id: registry.id
            })
        end

        registry_result

      {:error, _} ->
        # Check if it's a code-defined metric
        if is_code_defined_metric?(metric) do
          # Update or create display order entry for code-defined metric
          case by_metric(metric) do
            nil ->
              # Create a new display order entry
              add_metric(metric, category, group || "",
                label: label,
                style: style || "line",
                format: format || "",
                description: description || "",
                source_type: "code",
                source_id: nil
              )

            display_order ->
              # Update the existing display order entry
              __MODULE__.update(display_order, %{
                category: category,
                group: group || "",
                label: label,
                style: style || "line",
                format: format || "",
                description: description || "",
                source_type: "code",
                source_id: nil
              })
          end

          {:ok, nil}
        else
          # Metric not in registry or code, skip
          {:ok, nil}
        end
    end
  end

  defp sync_metadata_from_row(row) do
    {:error, "Invalid row format: #{inspect(row)}"}
  end

  defp is_new?(added_at, days \\ 14) do
    case added_at do
      nil ->
        false

      date ->
        threshold = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)
        DateTime.compare(date, threshold) == :gt
    end
  end

  @doc """
  Get a specific metric from the ordered metrics list by its name.
  Returns nil if the metric is not found.
  """
  def get_ordered_metric_by_name(metric_name) do
    get_ordered_metrics()
    |> Enum.find(fn metric -> metric.metric == metric_name end)
  end

  # Get metadata from the metric adapter
  defp get_metric_adapter_metadata(metric) do
    # For now, only use the Price metric adapter
    adapter = Sanbase.Price.MetricAdapter

    if metric in adapter.available_metrics() do
      case adapter.metadata(metric) do
        {:ok, metadata} ->
          # Check if the adapter provides category information
          if Map.has_key?(metadata, :category) do
            {:ok, metadata}
          else
            {:error, :no_category}
          end

        _ ->
          {:error, :metadata_error}
      end
    else
      {:error, :not_available}
    end
  end

  @doc """
  Import metrics to display order table and update registry from a CSV file.
  This is a convenience function that combines import_from_csv and update_registry_from_csv.

  Returns a map with counts of metrics added to display order, updated in display order,
  and updated in the registry.
  """
  def import_and_update_registry_from_csv(file_path) do
    # First import to display order
    display_order_result = import_from_csv(file_path)

    # Then update registry
    {registry_updated, registry_errors} = update_registry_from_csv(file_path)

    # Calculate metrics added and updated in display order
    {display_order_status, display_order_data} = display_order_result

    result = %{
      registry_updated: registry_updated,
      registry_errors: registry_errors
    }

    case display_order_status do
      :ok ->
        # Count metrics by action
        added = Enum.count(display_order_data, fn {action, _} -> action == :added end)
        updated = Enum.count(display_order_data, fn {action, _} -> action == :updated end)
        unchanged = Enum.count(display_order_data, fn {action, _} -> action == :unchanged end)

        # Get lists of metrics by action
        added_metrics =
          display_order_data
          |> Enum.filter(fn {action, _} -> action == :added end)
          |> Enum.map(fn {_, metric} -> metric end)

        updated_metrics =
          display_order_data
          |> Enum.filter(fn {action, _} -> action == :updated end)
          |> Enum.map(fn {_, metric} -> metric end)

        Map.merge(result, %{
          display_order_added: added,
          display_order_updated: updated,
          display_order_unchanged: unchanged,
          display_order_added_metrics: added_metrics,
          display_order_updated_metrics: updated_metrics,
          display_order_errors: []
        })

      :error ->
        # In the error case, display_order_data is the list of errors
        Map.merge(result, %{
          display_order_added: 0,
          display_order_updated: 0,
          display_order_unchanged: 0,
          display_order_added_metrics: [],
          display_order_updated_metrics: [],
          display_order_errors: display_order_data
        })
    end
  end

  @doc """
  Import metrics from a CSV file, update the registry, and print a summary.
  This is a convenience function that calls import_and_update_registry_from_csv
  and prints a summary of the results.
  """
  def import_and_update_with_summary(file_path) do
    result = import_and_update_registry_from_csv(file_path)

    # Print summary
    IO.puts("\n=== Import and Update Summary ===")
    IO.puts("Display Order:")
    IO.puts("  - Added: #{result.display_order_added} metrics")
    IO.puts("  - Updated: #{result.display_order_updated} metrics")
    IO.puts("  - Unchanged: #{result.display_order_unchanged} metrics")

    IO.puts("\nRegistry:")
    IO.puts("  - Updated: #{result.registry_updated} metrics")

    # Print errors if any
    if length(result.display_order_errors) > 0 do
      IO.puts("\nDisplay Order Errors:")

      Enum.each(result.display_order_errors, fn error ->
        IO.puts("  - #{error}")
      end)
    end

    if length(result.registry_errors) > 0 do
      IO.puts("\nRegistry Errors:")

      Enum.each(result.registry_errors, fn error ->
        IO.puts("  - #{error}")
      end)
    end

    # Group metrics by category and print
    if result.display_order_added > 0 or result.display_order_updated > 0 do
      metrics_by_category =
        (result.display_order_added_metrics ++ result.display_order_updated_metrics)
        |> Enum.map(fn metric -> by_metric(metric) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.group_by(fn metric -> metric.category end)

      IO.puts("\nMetrics by Category:")

      Enum.each(metrics_by_category, fn {category, metrics} ->
        IO.puts("  #{category}: #{length(metrics)} metrics")
      end)

      # Print total count
      total =
        Enum.reduce(metrics_by_category, 0, fn {_, metrics}, acc -> acc + length(metrics) end)

      IO.puts("\nTotal: #{total} metrics")
    end

    result
  end

  @doc """
  Extract metadata from a CSV file for use in forms.
  Returns a map with:
  - categories: ordered list of categories
  - groups_by_category: map of category to list of groups
  - chart_styles: list of all chart styles
  - formats: list of all formats
  """
  def extract_metadata_from_csv(file_path) do
    # Read the CSV file line by line
    {:ok, file} = File.open(file_path, [:read])

    # Skip header row
    IO.read(file, :line)

    # Initialize accumulators
    categories_order = %{}
    groups_by_category = %{}
    chart_styles = MapSet.new()
    formats = MapSet.new()

    # Process each line
    result =
      Stream.unfold(file, fn file ->
        case IO.read(file, :line) do
          :eof -> nil
          line -> {line, file}
        end
      end)
      |> Stream.map(&String.trim/1)
      |> Stream.filter(fn line -> line != "" end)
      |> Enum.reduce({categories_order, groups_by_category, chart_styles, formats}, fn line,
                                                                                       {cat_order,
                                                                                        groups,
                                                                                        styles,
                                                                                        fmts} ->
        # Parse the CSV line with proper handling of quoted fields
        fields = parse_csv_line(line)

        case fields do
          [_metric, _label, category, group, style, format, _description]
          when length(fields) >= 7 ->
            # Add category to order map if not present
            cat_order =
              if Map.has_key?(cat_order, category) do
                cat_order
              else
                Map.put(cat_order, category, map_size(cat_order) + 1)
              end

            # Add group to category's groups if not present
            groups =
              Map.update(groups, category, MapSet.new([group || ""]), fn group_set ->
                MapSet.put(group_set, group || "")
              end)

            # Add style and format to their sets
            styles = if style && style != "", do: MapSet.put(styles, style), else: styles
            fmts = if format && format != "", do: MapSet.put(fmts, format), else: fmts

            {cat_order, groups, styles, fmts}

          _ ->
            {cat_order, groups, styles, fmts}
        end
      end)

    File.close(file)

    # Convert the result to the final format
    {categories_order, groups_by_category, chart_styles, formats} = result

    # Sort categories by their order
    ordered_categories =
      categories_order
      |> Enum.sort_by(fn {_, order} -> order end)
      |> Enum.map(fn {category, _} -> category end)

    # Convert group MapSets to sorted lists
    groups_map =
      Map.new(groups_by_category, fn {category, group_set} ->
        {category, Enum.sort(MapSet.to_list(group_set))}
      end)

    # Return the structured metadata
    %{
      categories: ordered_categories,
      groups_by_category: groups_map,
      chart_styles: ["line" | MapSet.to_list(chart_styles) |> Enum.sort()],
      formats: ["" | MapSet.to_list(formats) |> Enum.sort()]
    }
  end

  @doc """
  Get all available chart styles from the registry.
  """
  def get_available_chart_styles do
    Registry.allowed_styles()
  end

  @doc """
  Get all available value formats from the registry.
  """
  def get_available_formats do
    Registry.allowed_formats()
  end

  @doc """
  Get all categories and their groups from the display order table.
  Returns a map with:
  - categories: ordered list of categories
  - groups_by_category: map of category to list of groups
  """
  def get_categories_and_groups do
    # Get all metrics from the display order table
    all_metrics = all()

    # Get categories in order
    categories_with_order =
      Repo.all(
        from(m in __MODULE__,
          group_by: m.category,
          select: {m.category, min(m.display_order)},
          order_by: [asc: min(m.display_order)]
        )
      )

    # Extract just the categories in the correct order
    ordered_categories = Enum.map(categories_with_order, fn {category, _} -> category end)

    # Group metrics by category and extract unique groups
    groups_by_category =
      all_metrics
      |> Enum.group_by(fn metric -> metric.category end)
      |> Map.new(fn {category, metrics} ->
        groups =
          metrics
          |> Enum.map(fn metric -> metric.group end)
          |> Enum.uniq()
          |> Enum.sort()

        {category, groups}
      end)

    %{
      categories: ordered_categories,
      groups_by_category: groups_by_category
    }
  end

  @doc """
  Create a new metric in the registry with metadata.
  This function creates both a registry entry and a display order entry.
  """
  def create_metric_with_metadata(metric_name, attrs) do
    # Extract metadata fields
    metadata = %{
      label: attrs[:label] || metric_name,
      category: attrs[:category] || "Uncategorized",
      group: attrs[:group] || "",
      style: attrs[:style] || "line",
      format: attrs[:format] || "",
      description: attrs[:description] || ""
    }

    # Create registry entry
    registry_attrs =
      Map.merge(metadata, %{
        metric: metric_name,
        internal_metric: attrs[:internal_metric] || metric_name,
        default_aggregation: attrs[:default_aggregation] || "last",
        min_interval: attrs[:min_interval] || "5m",
        access: attrs[:access] || "restricted",
        data_type: attrs[:data_type] || "timeseries"
      })

    # Start a transaction
    Repo.transaction(fn ->
      # Create registry entry
      case Registry.create(registry_attrs) do
        {:ok, registry} ->
          # Create display order entry with source_type and source_id
          display_order_opts = [
            label: metadata.label,
            style: metadata.style,
            format: metadata.format,
            description: metadata.description,
            source_type: "registry",
            source_id: registry.id
          ]

          case add_metric(metric_name, metadata.category, metadata.group, display_order_opts) do
            {:ok, display_order} -> {registry, display_order}
            {:error, error} -> Repo.rollback(error)
          end

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
  end

  @doc """
  Update a metric in the registry with metadata.
  This function updates both the registry entry and the display order entry.
  """
  def update_metric_with_metadata(metric_name, attrs) do
    # Extract metadata fields
    metadata = %{
      label: attrs[:label],
      category: attrs[:category],
      group: attrs[:group] || "",
      style: attrs[:style] || "line",
      format: attrs[:format] || "",
      description: attrs[:description] || ""
    }

    # Remove nil values
    metadata = Map.reject(metadata, fn {_, v} -> is_nil(v) end)

    # Start a transaction
    Repo.transaction(fn ->
      # Update registry entry if it exists
      registry_result =
        case Registry.by_name(metric_name) do
          {:ok, registry} ->
            Registry.update(registry, metadata)

          {:error, _} ->
            # Skip if not in registry
            {:ok, nil}
        end

      # Update display order entry if it exists
      display_order_result =
        case by_metric(metric_name) do
          nil ->
            # Create if not exists and category is provided
            if attrs[:category] do
              add_metric(metric_name, attrs[:category], attrs[:group] || "")
            else
              # Skip if no category
              {:ok, nil}
            end

          display_order ->
            # Check if we need to update category or group
            needs_update =
              (attrs[:category] && attrs[:category] != display_order.category) ||
                (attrs[:group] && attrs[:group] != display_order.group)

            if needs_update do
              # Create a changeset with only the fields we want to update
              changeset = changeset(display_order, %{})

              # Add category if provided and different
              changeset =
                if attrs[:category] && attrs[:category] != display_order.category do
                  Ecto.Changeset.put_change(changeset, :category, attrs[:category])
                else
                  changeset
                end

              # Add group if provided and different
              changeset =
                if attrs[:group] && attrs[:group] != display_order.group do
                  Ecto.Changeset.put_change(changeset, :group, attrs[:group])
                else
                  changeset
                end

              # Update if changeset has changes
              if changeset.changes != %{} do
                Repo.update(changeset)
              else
                {:ok, display_order}
              end
            else
              {:ok, display_order}
            end
        end

      case {registry_result, display_order_result} do
        {{:ok, registry}, {:ok, display_order}} ->
          {registry, display_order}

        {{:error, error}, _} ->
          Repo.rollback(error)

        {_, {:error, error}} ->
          Repo.rollback(error)
      end
    end)
  end

  # Determine if a metric is from the registry or defined in code
  defp determine_metric_source(metric) do
    case Registry.by_name(metric) do
      {:ok, registry} -> {"registry", registry.id}
      # Default to code
      {:error, _} -> {"code", nil}
    end
  end

  # Check if a metric is defined in code rather than in the registry
  defp is_code_defined_metric?(metric) do
    # For now, we'll consider any metric that's not in the registry as code-defined
    # This can be enhanced later with more specific logic if needed
    case Registry.by_name(metric) do
      {:ok, _} -> false
      {:error, _} -> true
    end
  end

  # Helper function to get value from registry if available, otherwise from display_order
  defp get_preferred_value(registry_metric, field, display_order_value) do
    registry_value = get_in(registry_metric || %{}, [Access.key(field)])

    if registry_value, do: registry_value, else: display_order_value
  end
end
