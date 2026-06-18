# Assign a list of metrics to a metric registry category
# (metric_category_mappings).
#
# Reads an explicit list of names from a file and assigns them all to one
# category given on the command line. The names must be the exact registry
# names, including template placeholders such as {{interval}} / {{timebound}},
# so they match metric_registry.metric directly (template rows have
# is_template = true). One name per line; blank lines are ignored.
#
# The target category must already exist in metric_categories.
#
# Behavior, per matching metric_registry row:
#   - no mapping at all          -> CREATE a mapping to the target category
#   - mapping already in target  -> SKIP (idempotent)
#   - mapping in other category  -> MOVE it to the target. group_id is cleared,
#     because groups belong to the old category (old group name is reported)
#   - mapping in other category, but the metric already has a target-category
#     mapping (pre-existing or created earlier in this run) -> MERGE: re-point
#     its metric_ui_metadata rows to the target mapping, then delete it.
#     Deleting without re-pointing would cascade-delete the UI metadata
#     (FK is on_delete: :delete_all).
#
# Names present in the file but absent from the registry are reported as MISSING
# and otherwise ignored. A single registry name may map to several registry rows
# (different data_type / fixed_parameters); every such row is categorized.
#
# All writes run in a single transaction; any failure rolls everything back.
#
# Run:
#   mix run scripts/move_metrics_to_category.exs --category="On-chain" --file=./onchain_metric_names.txt
#   mix run scripts/move_metrics_to_category.exs --category="On-chain Labels" --file=./onchain_labels_metric_names.txt --dry-run

defmodule MoveMetricsToCategory do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.UIMetadata

  def run(category_name, file, opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    category = fetch_category!(category_name)
    names = read_names!(file)
    metrics = fetch_metrics_by_name(names)

    found_names = metrics |> Enum.map(& &1.metric) |> MapSet.new()
    missing = Enum.reject(names, &MapSet.member?(found_names, &1))

    IO.puts(
      "Category #{inspect(category_name)} (id=#{category.id}): " <>
        "#{length(names)} names from #{file} -> #{length(metrics)} registry rows, " <>
        "#{length(missing)} names missing"
    )

    actions = Enum.flat_map(metrics, &plan_metric(&1, category))

    if dry_run? do
      print_report(category_name, actions, missing, dry_run?: true)
    else
      {:ok, _} = Repo.transaction(fn -> Enum.each(actions, &apply_action!(&1, category)) end)
      print_report(category_name, actions, missing, dry_run?: false)
    end

    %{category: category, actions: actions, missing: missing, summary: summarize(actions)}
  end

  defp read_names!(file) do
    unless File.exists?(file) do
      raise "File #{inspect(file)} not found."
    end

    file
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp fetch_category!(category_name) do
    case MetricCategory.get_by_name(category_name) do
      %MetricCategory{} = category ->
        category

      nil ->
        raise "Category #{inspect(category_name)} not found in metric_categories. " <>
                "Create it first, then re-run this script."
    end
  end

  defp fetch_metrics_by_name(names) do
    Repo.all(from(r in Registry, where: r.metric in ^names, order_by: r.metric))
  end

  # Returns the list of actions needed to put this metric in the target
  # category. Mappings are processed in order; once a target mapping exists
  # (pre-existing, or the first one moved/created), the remaining non-target
  # mappings are merged into it instead of moved, to avoid violating the
  # unique [metric_registry_id, category_id, group_id] index.
  defp plan_metric(registry, category) do
    mappings = mappings_for(registry.id)

    case mappings do
      [] ->
        [%{status: :create, metric: registry.metric, registry_id: registry.id}]

      mappings ->
        target_mapping = Enum.find(mappings, fn m -> m.category_id == category.id end)

        {actions, _} =
          Enum.map_reduce(mappings, target_mapping, fn mapping, target ->
            plan_mapping(mapping, target, registry, category)
          end)

        actions
    end
  end

  defp plan_mapping(mapping, target_mapping, registry, category) do
    base = %{
      metric: registry.metric,
      registry_id: registry.id,
      mapping_id: mapping.id,
      from_category: mapping.category.name,
      from_group: mapping.group && mapping.group.name
    }

    cond do
      mapping.category_id == category.id ->
        {Map.put(base, :status, :already_target), target_mapping}

      is_nil(target_mapping) ->
        # First non-target mapping and no target mapping exists yet:
        # this one gets moved and becomes the merge target for the rest.
        {Map.put(base, :status, :move), mapping}

      true ->
        action =
          base
          |> Map.put(:status, :merge)
          |> Map.put(:merge_into_mapping_id, target_mapping.id)

        {action, target_mapping}
    end
  end

  defp mappings_for(registry_id) do
    Repo.all(
      from(m in MetricCategoryMapping,
        where: m.metric_registry_id == ^registry_id,
        preload: [:category, :group],
        order_by: m.id
      )
    )
  end

  defp apply_action!(%{status: :already_target}, _category), do: :ok

  defp apply_action!(%{status: :create, registry_id: registry_id}, category) do
    {:ok, _} =
      MetricCategoryMapping.create(%{metric_registry_id: registry_id, category_id: category.id})

    :ok
  end

  defp apply_action!(%{status: :move, mapping_id: mapping_id}, category) do
    mapping = Repo.get!(MetricCategoryMapping, mapping_id)

    {:ok, _} =
      MetricCategoryMapping.update(mapping, %{category_id: category.id, group_id: nil})

    :ok
  end

  defp apply_action!(%{status: :merge} = action, _category) do
    %{mapping_id: mapping_id, merge_into_mapping_id: target_id} = action

    # Re-point UI metadata to the surviving target mapping before deleting,
    # otherwise the FK on_delete: :delete_all would wipe it.
    Repo.update_all(
      from(u in UIMetadata, where: u.metric_category_mapping_id == ^mapping_id),
      set: [metric_category_mapping_id: target_id]
    )

    mapping = Repo.get!(MetricCategoryMapping, mapping_id)
    {:ok, _} = MetricCategoryMapping.delete(mapping)

    :ok
  end

  defp print_report(category_name, actions, missing, dry_run?: dry_run?) do
    header = if dry_run?, do: "DRY RUN — no changes applied", else: "Applied changes"
    IO.puts("\n=== Assign metrics to #{inspect(category_name)} category — #{header} ===")

    Enum.each(actions, fn action -> IO.puts(format_action(action)) end)

    Enum.each(missing, fn name ->
      IO.puts("MISSING         #{pad(name, 60)} (no metric_registry row)")
    end)

    summary = summarize(actions)

    summary_line =
      [:create, :move, :merge, :already_target]
      |> Enum.map_join(" ", fn k -> "#{k}=#{Map.get(summary, k, 0)}" end)

    IO.puts("\nSummary: #{summary_line} missing=#{length(missing)}")
  end

  defp summarize(actions) do
    Enum.reduce(actions, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp format_action(%{status: :create} = a),
    do: "CREATE          #{pad(a.metric, 60)} (no mapping yet -> target)"

  defp format_action(%{status: :already_target} = a),
    do: "SKIP            #{pad(a.metric, 60)} (already in target#{group_suffix(a)})"

  defp format_action(%{status: :move} = a),
    do: "MOVE            #{pad(a.metric, 60)} #{a.from_category}#{group_suffix(a)} -> target"

  defp format_action(%{status: :merge} = a),
    do:
      "MERGE           #{pad(a.metric, 60)} #{a.from_category}#{group_suffix(a)} " <>
        "-> existing target mapping ##{a.merge_into_mapping_id}"

  defp group_suffix(%{from_group: nil}), do: ""
  defp group_suffix(%{from_group: group}), do: " / #{group}"
end

{parsed, _argv, _invalid} =
  OptionParser.parse(System.argv(),
    strict: [category: :string, file: :string, dry_run: :boolean]
  )

category = parsed[:category] || raise "Missing required --category=\"<name>\""
file = parsed[:file] || raise "Missing required --file=<path>"
dry_run? = Keyword.get(parsed, :dry_run, false)

MoveMetricsToCategory.run(category, file, dry_run: dry_run?)
