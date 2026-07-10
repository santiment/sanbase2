# Move the metrics listed in a file from the "On-chain" category to the
# "On-chain Labels" category in the metric registry categorization
# (metric_category_mappings).
#
# ## Input file
#
# One metric name per line; blank lines and surrounding whitespace are
# ignored, duplicate names are processed once. Names must be the exact
# registry names, including template placeholders such as {{interval}} /
# {{lower}}, so they match metric_registry.metric directly. Example:
#
#     aave_v2_revenue
#     makerdao_action_deposits
#     percent_of_total_supply_on_exchanges_change_{{interval}}
#     holders_labeled_distribution_{{lower}}_to_{{upper}}
#     uniswap_top_claimers
#
# ## Name resolution
#
# Each name is resolved to metric_registry rows first. A single registry name
# may map to several rows (different data_type / fixed_parameters); every such
# row is processed.
#
# Names absent from the registry but implemented by a code metric adapter
# (per Sanbase.Metric.Helper.metric_to_module_map/0) are categorized as code
# metrics: their mappings use the module + metric columns of
# metric_category_mappings instead of metric_registry_id, with the module
# stored as its inspect/1 string (e.g. "Sanbase.Clickhouse.Uniswap.MetricAdapter"
# for uniswap_top_claimers) — the same format the categorization admin UI uses.
#
# Names matching neither are reported as MISSING and otherwise ignored.
#
# ## Behavior, per matching metric (registry row or code metric)
#
#   - no mapping at all               -> CREATE a mapping to On-chain Labels
#   - mapping already in Labels       -> SKIP (idempotent)
#   - mapping in On-chain             -> MOVE it to On-chain Labels. group_id is
#     cleared, because groups belong to the old category (old group is reported)
#   - mapping in On-chain, but the metric already has an On-chain Labels mapping
#     (pre-existing or created earlier in this run) -> MERGE: re-point its
#     metric_ui_metadata rows to the Labels mapping, then delete it. Deleting
#     without re-pointing would cascade-delete the UI metadata
#     (FK is on_delete: :delete_all).
#   - mapping in any other category   -> left untouched, reported as KEEP
#
# All writes run in a single transaction; any failure rolls everything back.
# The script is idempotent — re-running it reports SKIP for already-moved
# metrics and changes nothing.
#
# ## Usage
#
#   # Report what would change, write nothing:
#   mix run scripts/move_onchain_metrics_to_onchain_labels_category.exs --dry-run
#
#   # Apply (reads ./onchain_labels_metric_names.txt by default):
#   mix run scripts/move_onchain_metrics_to_onchain_labels_category.exs
#
#   # Use another names file:
#   mix run scripts/move_onchain_metrics_to_onchain_labels_category.exs \
#     --file=./uncategorized_onchain_labels_metric_names.txt --dry-run
#
# ## Example output
#
#   "On-chain" (id=2) -> "On-chain Labels" (id=3): 246 names from
#   ./onchain_labels_metric_names.txt -> 244 registry rows, 1 code metrics, 1 names missing
#
#   === Move metrics "On-chain" -> "On-chain Labels" — DRY RUN — no changes applied ===
#   MOVE            aave_v2_revenue                     On-chain / Aave v2 -> On-chain Labels
#   CREATE          active_withdrawals                  (no mapping yet -> On-chain Labels)
#   CREATE          uniswap_top_claimers                (code metric Sanbase.Clickhouse.Uniswap.MetricAdapter, no mapping yet -> On-chain Labels)
#   SKIP            makerdao_action_deposits            (already in On-chain Labels)
#   KEEP            some_defi_metric                    (in Financial, not On-chain — untouched)
#   MISSING         no_such_metric                      (no metric_registry row or code adapter metric)
#
#   Summary: create=2 move=1 merge=0 already_target=1 keep=1 missing=1

defmodule MoveOnchainMetricsToOnchainLabelsCategory do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Helper
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.UIMetadata

  @source_category_name "On-chain"
  @target_category_name "On-chain Labels"
  @default_file "./onchain_labels_metric_names.txt"

  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    file = Keyword.get(opts, :file, @default_file)

    source = fetch_category!(@source_category_name)
    target = fetch_category!(@target_category_name)
    names = read_names!(file)
    registry_metrics = fetch_metrics_by_name(names)

    found_names = registry_metrics |> Enum.map(& &1.metric) |> MapSet.new()
    non_registry_names = Enum.reject(names, &MapSet.member?(found_names, &1))
    {code_metrics, missing} = resolve_code_metrics(non_registry_names)

    IO.puts(
      "#{inspect(@source_category_name)} (id=#{source.id}) -> " <>
        "#{inspect(@target_category_name)} (id=#{target.id}): " <>
        "#{length(names)} names from #{file} -> #{length(registry_metrics)} registry rows, " <>
        "#{length(code_metrics)} code metrics, #{length(missing)} names missing"
    )

    actions =
      Enum.flat_map(registry_metrics, &plan_registry_metric(&1, source, target)) ++
        Enum.flat_map(code_metrics, &plan_code_metric(&1, source, target))

    if dry_run? do
      print_report(actions, missing, dry_run?: true)
    else
      {:ok, _} = Repo.transaction(fn -> Enum.each(actions, &apply_action!(&1, target)) end)
      print_report(actions, missing, dry_run?: false)
    end

    %{actions: actions, missing: missing, summary: summarize(actions)}
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

  # Names not present in the registry are looked up among the code metric
  # adapters. The module is stored in the mapping as its inspect/1 string,
  # the same format the categorization admin UI uses.
  defp resolve_code_metrics(names) do
    metric_to_module = Helper.metric_to_module_map()

    names
    |> Enum.split_with(&Map.has_key?(metric_to_module, &1))
    |> then(fn {code_names, missing} ->
      code_metrics =
        Enum.map(code_names, fn name ->
          %{metric: name, module: inspect(Map.fetch!(metric_to_module, name))}
        end)

      {code_metrics, missing}
    end)
  end

  # Returns the list of actions needed to move this metric from On-chain to
  # On-chain Labels. Mappings are processed in order; once a Labels mapping
  # exists (pre-existing, or the first one moved), the remaining On-chain
  # mappings are merged into it instead of moved, to avoid violating the
  # unique [metric_registry_id, category_id, group_id] (or
  # [module, metric, category_id, group_id]) index. Mappings in categories
  # other than On-chain are left untouched.
  defp plan_registry_metric(registry, source, target) do
    ident = %{metric: registry.metric, registry_id: registry.id}
    plan_mappings(registry_mappings_for(registry.id), ident, source, target)
  end

  defp plan_code_metric(code_metric, source, target) do
    ident = %{metric: code_metric.metric, module: code_metric.module}
    plan_mappings(code_mappings_for(code_metric), ident, source, target)
  end

  defp plan_mappings(mappings, ident, source, target) do
    case mappings do
      [] ->
        [Map.put(ident, :status, :create)]

      mappings ->
        target_mapping = Enum.find(mappings, fn m -> m.category_id == target.id end)

        {actions, _} =
          Enum.map_reduce(mappings, target_mapping, fn mapping, target_acc ->
            plan_mapping(mapping, target_acc, ident, source, target)
          end)

        actions
    end
  end

  defp plan_mapping(mapping, target_mapping, ident, source, target) do
    base =
      Map.merge(ident, %{
        mapping_id: mapping.id,
        from_category: mapping.category.name,
        from_group: mapping.group && mapping.group.name
      })

    cond do
      mapping.category_id == target.id ->
        {Map.put(base, :status, :already_target), target_mapping}

      mapping.category_id != source.id ->
        # Not an On-chain mapping — this script only moves out of On-chain.
        {Map.put(base, :status, :keep), target_mapping}

      is_nil(target_mapping) ->
        # First On-chain mapping and no Labels mapping exists yet:
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

  defp registry_mappings_for(registry_id) do
    Repo.all(
      from(m in MetricCategoryMapping,
        where: m.metric_registry_id == ^registry_id,
        preload: [:category, :group],
        order_by: m.id
      )
    )
  end

  defp code_mappings_for(%{metric: metric, module: module}) do
    Repo.all(
      from(m in MetricCategoryMapping,
        where: m.module == ^module and m.metric == ^metric,
        preload: [:category, :group],
        order_by: m.id
      )
    )
  end

  defp apply_action!(%{status: :already_target}, _target), do: :ok
  defp apply_action!(%{status: :keep}, _target), do: :ok

  defp apply_action!(%{status: :create, registry_id: registry_id}, target) do
    {:ok, _} =
      MetricCategoryMapping.create(%{metric_registry_id: registry_id, category_id: target.id})

    :ok
  end

  defp apply_action!(%{status: :create, module: module, metric: metric}, target) do
    {:ok, _} =
      MetricCategoryMapping.create(%{module: module, metric: metric, category_id: target.id})

    :ok
  end

  defp apply_action!(%{status: :move, mapping_id: mapping_id}, target) do
    mapping = Repo.get!(MetricCategoryMapping, mapping_id)

    {:ok, _} =
      MetricCategoryMapping.update(mapping, %{category_id: target.id, group_id: nil})

    :ok
  end

  defp apply_action!(%{status: :merge} = action, _target) do
    %{mapping_id: mapping_id, merge_into_mapping_id: target_id} = action

    # Re-point UI metadata to the surviving Labels mapping before deleting,
    # otherwise the FK on_delete: :delete_all would wipe it.
    Repo.update_all(
      from(u in UIMetadata, where: u.metric_category_mapping_id == ^mapping_id),
      set: [metric_category_mapping_id: target_id]
    )

    mapping = Repo.get!(MetricCategoryMapping, mapping_id)
    {:ok, _} = MetricCategoryMapping.delete(mapping)

    :ok
  end

  defp print_report(actions, missing, dry_run?: dry_run?) do
    header = if dry_run?, do: "DRY RUN — no changes applied", else: "Applied changes"

    IO.puts(
      "\n=== Move metrics #{inspect(@source_category_name)} -> " <>
        "#{inspect(@target_category_name)} — #{header} ==="
    )

    Enum.each(actions, fn action -> IO.puts(format_action(action)) end)

    Enum.each(missing, fn name ->
      IO.puts("MISSING         #{pad(name, 60)} (no metric_registry row or code adapter metric)")
    end)

    summary = summarize(actions)

    summary_line =
      [:create, :move, :merge, :already_target, :keep]
      |> Enum.map_join(" ", fn k -> "#{k}=#{Map.get(summary, k, 0)}" end)

    IO.puts("\nSummary: #{summary_line} missing=#{length(missing)}")
  end

  defp summarize(actions) do
    Enum.reduce(actions, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp format_action(%{status: :create, module: module} = a),
    do:
      "CREATE          #{pad(a.metric, 60)} (code metric #{module}, " <>
        "no mapping yet -> #{@target_category_name})"

  defp format_action(%{status: :create} = a),
    do: "CREATE          #{pad(a.metric, 60)} (no mapping yet -> #{@target_category_name})"

  defp format_action(%{status: :already_target} = a),
    do: "SKIP            #{pad(a.metric, 60)} (already in #{@target_category_name}#{group_suffix(a)})"

  defp format_action(%{status: :keep} = a),
    do: "KEEP            #{pad(a.metric, 60)} (in #{a.from_category}#{group_suffix(a)}, not On-chain — untouched)"

  defp format_action(%{status: :move} = a),
    do: "MOVE            #{pad(a.metric, 60)} #{a.from_category}#{group_suffix(a)} -> #{@target_category_name}"

  defp format_action(%{status: :merge} = a),
    do:
      "MERGE           #{pad(a.metric, 60)} #{a.from_category}#{group_suffix(a)} " <>
        "-> existing #{@target_category_name} mapping ##{a.merge_into_mapping_id}"

  defp group_suffix(%{from_group: nil}), do: ""
  defp group_suffix(%{from_group: group}), do: " / #{group}"
end

{parsed, _argv, _invalid} =
  OptionParser.parse(System.argv(), strict: [file: :string, dry_run: :boolean])

opts = [dry_run: Keyword.get(parsed, :dry_run, false)]
opts = if parsed[:file], do: Keyword.put(opts, :file, parsed[:file]), else: opts

MoveOnchainMetricsToOnchainLabelsCategory.run(opts)
