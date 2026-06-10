# Move all social-related metrics to the "Social" category in the metric
# registry categorization (metric_category_mappings).
#
# A metric is considered social-related when its registry name contains any of:
# social, sentiment, text, docs (case-insensitive).
#
# Behavior, per matching metric_registry row:
#   - no mapping at all          -> CREATE a mapping to Social (no group)
#   - mapping already in Social  -> SKIP (idempotent)
#   - mapping in other category  -> MOVE it to Social. group_id is cleared,
#     because groups belong to the old category (old group name is reported)
#   - mapping in other category, but the metric already has a Social mapping
#     (pre-existing or created earlier in this run) -> MERGE: re-point its
#     metric_ui_metadata rows to the Social mapping, then delete it. Deleting
#     without re-pointing would cascade-delete the UI metadata
#     (FK is on_delete: :delete_all).
#
# All writes run in a single transaction; any failure rolls everything back.
#
# Run:
#   mix run scripts/move_social_metrics_to_social_category.exs            # apply
#   mix run scripts/move_social_metrics_to_social_category.exs --dry-run  # report only

defmodule MoveSocialMetricsToSocialCategory do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.UIMetadata

  @category_name "Social"
  @keywords ~w(social sentiment text docs)

  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    social = fetch_social_category!()
    metrics = fetch_matching_metrics()

    IO.puts(
      "Found #{length(metrics)} registry metrics matching #{inspect(@keywords)} " <>
        "(Social category id=#{social.id})"
    )

    actions = Enum.flat_map(metrics, &plan_metric(&1, social))

    if dry_run? do
      print_report(actions, dry_run?: true)
    else
      {:ok, _} = Repo.transaction(fn -> Enum.each(actions, &apply_action!(&1, social)) end)
      print_report(actions, dry_run?: false)
    end

    %{actions: actions, summary: summarize(actions)}
  end

  defp fetch_social_category!() do
    case MetricCategory.get_by_name(@category_name) do
      %MetricCategory{} = category ->
        category

      nil ->
        raise "Category #{inspect(@category_name)} not found in metric_categories. " <>
                "Create it first, then re-run this script."
    end
  end

  defp fetch_matching_metrics() do
    conditions =
      Enum.reduce(@keywords, dynamic(false), fn keyword, dyn ->
        dynamic([r], ^dyn or ilike(r.metric, ^"%#{keyword}%"))
      end)

    Repo.all(from(r in Registry, where: ^conditions, order_by: r.metric))
  end

  # Returns the list of actions needed to put this metric in the Social
  # category. Mappings are processed in order; once a Social mapping exists
  # (pre-existing, or the first one moved/created), the remaining non-Social
  # mappings are merged into it instead of moved, to avoid violating the
  # unique [metric_registry_id, category_id, group_id] index.
  defp plan_metric(registry, social) do
    mappings = mappings_for(registry.id)

    case mappings do
      [] ->
        [%{status: :create, metric: registry.metric, registry_id: registry.id}]

      mappings ->
        social_mapping = Enum.find(mappings, fn m -> m.category_id == social.id end)

        {actions, _} =
          Enum.map_reduce(mappings, social_mapping, fn mapping, social_target ->
            plan_mapping(mapping, social_target, registry, social)
          end)

        actions
    end
  end

  defp plan_mapping(mapping, social_target, registry, social) do
    base = %{
      metric: registry.metric,
      registry_id: registry.id,
      mapping_id: mapping.id,
      from_category: mapping.category.name,
      from_group: mapping.group && mapping.group.name
    }

    cond do
      mapping.category_id == social.id ->
        {Map.put(base, :status, :already_social), social_target}

      is_nil(social_target) ->
        # First non-Social mapping and no Social mapping exists yet:
        # this one gets moved and becomes the merge target for the rest.
        {Map.put(base, :status, :move), mapping}

      true ->
        action =
          base
          |> Map.put(:status, :merge)
          |> Map.put(:merge_into_mapping_id, social_target.id)

        {action, social_target}
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

  defp apply_action!(%{status: :already_social}, _social), do: :ok

  defp apply_action!(%{status: :create, registry_id: registry_id}, social) do
    {:ok, _} =
      MetricCategoryMapping.create(%{metric_registry_id: registry_id, category_id: social.id})

    :ok
  end

  defp apply_action!(%{status: :move, mapping_id: mapping_id}, social) do
    mapping = Repo.get!(MetricCategoryMapping, mapping_id)

    {:ok, _} =
      MetricCategoryMapping.update(mapping, %{category_id: social.id, group_id: nil})

    :ok
  end

  defp apply_action!(%{status: :merge} = action, _social) do
    %{mapping_id: mapping_id, merge_into_mapping_id: target_id} = action

    # Re-point UI metadata to the surviving Social mapping before deleting,
    # otherwise the FK on_delete: :delete_all would wipe it.
    Repo.update_all(
      from(u in UIMetadata, where: u.metric_category_mapping_id == ^mapping_id),
      set: [metric_category_mapping_id: target_id]
    )

    mapping = Repo.get!(MetricCategoryMapping, mapping_id)
    {:ok, _} = MetricCategoryMapping.delete(mapping)

    :ok
  end

  defp print_report(actions, dry_run?: dry_run?) do
    header = if dry_run?, do: "DRY RUN — no changes applied", else: "Applied changes"
    IO.puts("\n=== Move social metrics to #{inspect(@category_name)} category — #{header} ===")

    Enum.each(actions, fn action -> IO.puts(format_action(action)) end)

    summary = summarize(actions)

    summary_line =
      [:create, :move, :merge, :already_social]
      |> Enum.map_join(" ", fn k -> "#{k}=#{Map.get(summary, k, 0)}" end)

    IO.puts("\nSummary: #{summary_line}")
  end

  defp summarize(actions) do
    Enum.reduce(actions, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp format_action(%{status: :create} = a),
    do: "CREATE          #{pad(a.metric, 60)} (no mapping yet -> Social)"

  defp format_action(%{status: :already_social} = a),
    do: "SKIP            #{pad(a.metric, 60)} (already in Social#{group_suffix(a)})"

  defp format_action(%{status: :move} = a),
    do: "MOVE            #{pad(a.metric, 60)} #{a.from_category}#{group_suffix(a)} -> Social"

  defp format_action(%{status: :merge} = a),
    do:
      "MERGE           #{pad(a.metric, 60)} #{a.from_category}#{group_suffix(a)} " <>
        "-> existing Social mapping ##{a.merge_into_mapping_id}"

  defp group_suffix(%{from_group: nil}), do: ""
  defp group_suffix(%{from_group: group}), do: " / #{group}"
end

dry_run? = "--dry-run" in System.argv()
MoveSocialMetricsToSocialCategory.run(dry_run: dry_run?)
