defmodule Sanbase.Repo.Migrations.MergeMarketMetricCategories do
  use Ecto.Migration

  require Logger

  # Merges the legacy `Financial`, `Derivatives` and `Indicators` categories into
  # one `Market` category - the name that `Sanbase.Billing.Plan.Bundle.Package`
  # gives the Market data package. Until this runs,
  # `PackageSnapshot.materialize/0` refuses to build with
  # "1 package(s) name a metric category that does not exist".
  #
  # The other four packages already match by name (`Development`, `Social`,
  # `On-chain`, `On-chain Labels`), so this is the only category-level change
  # needed. The Notion pages call two of them "Social Sentiment" and
  # "Onchain(Core)" - do NOT rename the rows to match. Those are the marketing
  # names and already live in `Package.name`; `Package.category` is the database
  # key. See the moduledoc of `Bundle.Package`.
  #
  # Groups are deliberately not created. The Notion taxonomy for Market
  # (Pricing, Marketcap, Volume, ETF, Indicators, NFT, Funding rates, Open
  # Interest, Deprecated) is separate work and nothing regresses by waiting:
  # every mapping in these three categories was copied over from the v1
  # taxonomy with `group_id` NULL, so they are ungrouped already.
  #
  # `metric_category_mappings.display_order` is also left alone. Three
  # independent sequences collapsing into one category interleaves them, which
  # only affects presentation order in the admin UI and in
  # `getOrderedMetricsV2` - the package snapshot sorts alphabetically
  # (`package_snapshot.ex`), so billing is order-independent. A follow-up
  # migration renumbers them.
  #
  # v1 (`metric_display_order`, `ui_metadata_categories`, `ui_metadata_groups`)
  # is untouched, so `getOrderedMetrics`, which powers the web app, cannot be
  # affected by any of this.
  #
  # Runs as a no-op when none of the three source categories exist - a fresh
  # dev/test database, an already-merged one, or a second run.

  @target "Market"

  # Financial was display_order 1, so 1 is free once it is gone and the
  # survivors keep 2, 3, 6, 7. The gaps are invisible - nothing requires
  # display_order to be contiguous and no index requires it to be unique - so
  # the remaining categories are not renumbered. The orders are kept here only
  # so that `down` can put the rows back the way it found them.
  @target_display_order 1
  @sources [{"Financial", 1}, {"Derivatives", 4}, {"Indicators", 5}]
  @source_names Enum.map(@sources, &elem(&1, 0))

  def up() do
    case category_ids(@source_names) do
      [] ->
        log("none of #{Enum.join(@source_names, ", ")} exist, nothing to merge")

      source_ids ->
        target_id = upsert_target()

        refuse_on_group_name_clash!([target_id | source_ids])
        move_groups(source_ids, target_id)
        drop_duplicate_mappings([target_id | source_ids], target_id)
        move_mappings(source_ids, target_id)
        delete_merged_categories(source_ids)
    end
  end

  # Recreates the three categories, empty, with the display_order values they
  # had. It does not put the metrics back - which category each mapping came
  # from is not recorded anywhere, so that would have to come from a backup.
  # Market is left in place because the mappings now point at it.
  def down() do
    Enum.each(@sources, fn {name, display_order} ->
      query!(
        """
        INSERT INTO metric_categories (name, display_order, inserted_at, updated_at)
        VALUES ($1, $2, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')
        ON CONFLICT (name) DO NOTHING
        """,
        [name, display_order]
      )
    end)

    log(
      "#{Enum.join(@source_names, ", ")} recreated empty - metric assignments were " <>
        "not restored, the mappings still point at #{@target}"
    )
  end

  defp upsert_target() do
    query!(
      """
      INSERT INTO metric_categories (name, display_order, inserted_at, updated_at)
      VALUES ($1, $2, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')
      ON CONFLICT (name) DO NOTHING
      """,
      [@target, @target_display_order]
    )

    [target_id] = category_ids([@target])
    target_id
  end

  # metric_groups has a unique index on (name, category_id). The v1 taxonomy
  # gave these three categories no groups at all, so in practice there is
  # nothing to clash - but a group added by hand through the admin UI could
  # collide, and picking a winner is not a decision a migration should make.
  defp refuse_on_group_name_clash!(category_ids) do
    clashing =
      "SELECT name FROM metric_groups WHERE category_id = ANY($1) GROUP BY name HAVING count(*) > 1 ORDER BY name"
      |> query!([category_ids])
      |> flat_rows()

    if clashing != [] do
      raise """
      Cannot merge into #{@target}: group name(s) present in more than one of the \
      merged categories: #{Enum.join(clashing, ", ")}.

      Rename or merge those groups by hand first - metric_groups is unique on \
      (name, category_id).
      """
    end
  end

  defp move_groups(source_ids, target_id) do
    %{num_rows: moved} =
      query!(
        """
        UPDATE metric_groups
        SET category_id = $1, updated_at = now() AT TIME ZONE 'UTC'
        WHERE category_id = ANY($2)
        """,
        [target_id, source_ids]
      )

    log("#{moved} group(s) moved to #{@target}")
  end

  # metric_category_mappings is unique on (metric_registry_id, category_id,
  # group_id) and on (module, metric, category_id, group_id), both partial and
  # both with nulls_distinct: false. A metric mapped in two of the merged
  # categories therefore becomes a duplicate key the moment both rows point at
  # Market, so the duplicates have to go first.
  #
  # Partitioning by all four identifier columns is equivalent to partitioning by
  # whichever pair of columns the applicable index uses: the
  # :only_one_metric_identifier check constraint makes the two shapes disjoint,
  # so module/metric are always NULL on a registry row and metric_registry_id is
  # always NULL on a module row.
  defp drop_duplicate_mappings(category_ids, target_id) do
    pairs =
      """
      SELECT id, keep_id
      FROM (
        SELECT m.id,
               first_value(m.id) OVER (
                 PARTITION BY m.metric_registry_id, m.module, m.metric, m.group_id
                 ORDER BY (m.category_id = $2) DESC, m.id ASC
               ) AS keep_id
        FROM metric_category_mappings m
        WHERE m.category_id = ANY($1)
      ) ranked
      WHERE id <> keep_id
      """
      |> query!([category_ids, target_id])
      |> Map.fetch!(:rows)

    case Enum.unzip(Enum.map(pairs, fn [id, keep_id] -> {id, keep_id} end)) do
      {[], []} ->
        log("no duplicate mappings to drop")

      {duplicate_ids, keep_ids} ->
        # Reparent the UI metadata of every duplicate onto the row that is kept
        # before deleting it - metric_ui_metadata.metric_category_mapping_id is
        # ON DELETE CASCADE, so a plain delete would destroy it. Only the parent
        # changes, and metric_ui_metadata's unique indexes are on (ui_key) and
        # (metric, args), so this cannot conflict.
        %{num_rows: reparented} =
          query!(
            """
            UPDATE metric_ui_metadata u
            SET metric_category_mapping_id = pair.keep_id,
                updated_at = now() AT TIME ZONE 'UTC'
            FROM unnest($1::bigint[], $2::bigint[]) AS pair(duplicate_id, keep_id)
            WHERE u.metric_category_mapping_id = pair.duplicate_id
            """,
            [duplicate_ids, keep_ids]
          )

        %{num_rows: dropped} =
          query!("DELETE FROM metric_category_mappings WHERE id = ANY($1)", [duplicate_ids])

        log(
          "#{dropped} duplicate mapping(s) dropped, #{reparented} ui_metadata row(s) reparented"
        )
    end
  end

  defp move_mappings(source_ids, target_id) do
    %{num_rows: moved} =
      query!(
        """
        UPDATE metric_category_mappings
        SET category_id = $1, updated_at = now() AT TIME ZONE 'UTC'
        WHERE category_id = ANY($2)
        """,
        [target_id, source_ids]
      )

    log("#{moved} mapping(s) moved to #{@target}")
  end

  # Both metric_groups.category_id and metric_category_mappings.category_id are
  # ON DELETE CASCADE, so this delete silently destroys anything the steps above
  # failed to move. They are unconditional and cannot leave anything behind,
  # which is exactly why a leftover means a bug rather than data to discard -
  # fail instead of cascading.
  defp delete_merged_categories(source_ids) do
    leftover_mappings = count("metric_category_mappings", source_ids)
    leftover_groups = count("metric_groups", source_ids)

    if leftover_mappings > 0 or leftover_groups > 0 do
      raise "Refusing to delete the merged categories: #{leftover_mappings} mapping(s) " <>
              "and #{leftover_groups} group(s) still reference them"
    end

    %{num_rows: deleted} =
      query!("DELETE FROM metric_categories WHERE id = ANY($1)", [source_ids])

    log("#{deleted} merged categor(ies) deleted: #{Enum.join(@source_names, ", ")}")
  end

  defp count(table, category_ids) do
    %{rows: [[count]]} =
      query!("SELECT count(*) FROM #{table} WHERE category_id = ANY($1)", [category_ids])

    count
  end

  defp category_ids(names) do
    "SELECT id FROM metric_categories WHERE name = ANY($1) ORDER BY id"
    |> query!([names])
    |> flat_rows()
  end

  defp flat_rows(%{rows: rows}), do: List.flatten(rows)

  defp query!(sql, params), do: repo().query!(sql, params)

  defp log(message), do: Logger.info("[merge_market_metric_categories] #{message}")
end
