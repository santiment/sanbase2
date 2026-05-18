defmodule SimulateMissingSyncChangelog do
  @moduledoc """
  Local-only reproduction helper for the metric registry "missing diff"
  bug.

  ## What this is

  A throwaway script that forces a single metric in the local DB into the
  exact state that makes the admin UI render the
  "This should not be visible." fallback when the user clicks
  "(click to see diff)" next to a `NOT SYNCED` metric.

  The fallback lives in
  `lib/sanbase_web/live/metric_registry/metric_registry_index_live.ex`
  (`diff_since_last_sync/1`) and fires when
  `Sanbase.Metric.Registry.Changelog.state_before_last_sync/2` returns
  `{:error, _}` — i.e. no usable baseline row exists in the
  `metric_registry_changelog` table.

  ## Why this exists

  On staging some metrics have `sync_status = "not_synced"` and a
  `last_sync_datetime` set, but no `sync_apply` changelog row at or
  before that datetime (legacy data predating changelog
  instrumentation). The diff view can't reconstruct a baseline and shows
  the fallback. To verify any code fix we need a way to recreate that
  exact state locally — that's what this script does.

  ## What it does

  `setup/1` (given a metric name or `%Registry{}`):

    1. Snapshots the original `sync_status`, `last_sync_datetime`,
       `human_readable_name`, `is_verified`, and the ids of any
       `sync_apply` changelog rows it deletes.
    2. Deletes every `sync_apply` changelog row for that metric so the
       datetime branch of `state_before_last_sync/2` finds nothing.
    3. Mutates the metric: `sync_status -> "not_synced"`,
       `last_sync_datetime -> 2025-01-01`, `is_verified -> false`, and
       appends " (simulated)" to `human_readable_name` so the diff has
       at least one visible field change.
    4. Inserts a synthetic `change_request_approve` changelog row whose
       `old` is the pre-mutation JSON. This is required so the metric
       appears in `Changelog.metric_registry_ids_with_changes/0` and the
       "(click to see diff)" link renders at all.

  `cleanup/1` restores `sync_status`, `last_sync_datetime`,
  `is_verified`, `human_readable_name`, and deletes the synthetic
  changelog row. The deleted `sync_apply` rows are NOT restored — their
  ids are kept in the snapshot for manual recovery if you care.

  ## Safety

  `guard!/0` refuses to run if any of these hold:

    * `DATABASE_URL` is set (prod/stage runtime sets it in
      `config/runtime.exs`).
    * `RELEASE_NAME` is set (mix release / remote_console).
    * `Node.self() != :nonode@nohost` (named node, i.e. a release or
      distributed Erlang session).

  This makes it impossible to accidentally run against the production
  DB via `kubectl exec` + `bin/sanbase remote_console`.

  ## Usage

      # Paste this whole file into a local `iex -S mix` session, then:
      {:ok, snap} = SimulateMissingSyncChangelog.setup("price_usd")
      # Open /admin/metric_registry, find the metric, click
      # "(click to see diff)" — fallback (or fix) renders.
      SimulateMissingSyncChangelog.cleanup(snap)
  """

  import Ecto.Query

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.Changelog
  alias Sanbase.Repo

  @fake_last_sync ~U[2025-01-01 00:00:00Z]

  # Hard guard: refuse to run anywhere that looks like a deployed env.
  # - DATABASE_URL is set in prod/stage via config/runtime.exs (line 130).
  # - Mix releases set RELEASE_NAME / RELEASE_NODE; not set in local `iex -S mix`.
  # - In a release / remote_console, Node.self() looks like `sanbase@host`.
  #   In local iex it's :"nonode@nohost".
  defp guard!() do
    cond do
      System.get_env("DATABASE_URL") not in [nil, ""] ->
        raise "Refusing to run: DATABASE_URL is set (looks like a deployed env)."

      System.get_env("RELEASE_NAME") not in [nil, ""] ->
        raise "Refusing to run: RELEASE_NAME is set (running inside a release / remote_console)."

      Node.self() != :"nonode@nohost" ->
        raise "Refusing to run: node is named #{inspect(Node.self())} (looks like remote_console)."

      true ->
        :ok
    end
  end

  def setup(metric_name) when is_binary(metric_name) do
    guard!()
    metric = Repo.get_by!(Registry, metric: metric_name)
    setup(metric)
  end

  def setup(%Registry{} = metric) do
    guard!()
    snapshot = %{
      metric_id: metric.id,
      sync_status: metric.sync_status,
      last_sync_datetime: metric.last_sync_datetime,
      human_readable_name: metric.human_readable_name,
      is_verified: metric.is_verified,
      deleted_sync_apply_ids: delete_sync_apply_rows(metric.id)
    }

    # Encode "before" state for the synthetic changelog row, so the diff
    # has something to render against. Includes the original
    # human_readable_name which we mutate below.
    old_json = Jason.encode!(metric)

    {:ok, updated} =
      metric
      |> Ecto.Changeset.change(%{
        sync_status: "not_synced",
        last_sync_datetime: @fake_last_sync,
        is_verified: false,
        human_readable_name: "#{metric.human_readable_name} (simulated)"
      })
      |> Repo.update()

    {:ok, inserted} =
      %Changelog{}
      |> Changelog.changeset(%{
        metric_registry_id: updated.id,
        old: old_json,
        new: Jason.encode!(updated),
        change_trigger: "change_request_approve"
      })
      |> Repo.insert()

    snapshot = Map.put(snapshot, :inserted_changelog_id, inserted.id)

    IO.puts("Metric #{updated.metric} (id=#{updated.id}) primed.")
    IO.puts("Open the admin UI and click '(click to see diff)' to verify.")
    {:ok, snapshot}
  end

  def cleanup(%{metric_id: id} = snapshot) do
    guard!()
    Repo.get!(Changelog, snapshot.inserted_changelog_id) |> Repo.delete!()

    metric = Repo.get!(Registry, id)

    metric
    |> Ecto.Changeset.change(%{
      sync_status: snapshot.sync_status,
      last_sync_datetime: snapshot.last_sync_datetime,
      is_verified: snapshot.is_verified,
      human_readable_name: snapshot.human_readable_name
    })
    |> Repo.update!()

    IO.puts(
      "Restored metric #{metric.metric} (id=#{id}). Note: deleted sync_apply rows are NOT restored."
    )

    :ok
  end

  defp delete_sync_apply_rows(metric_id) do
    ids =
      from(c in Changelog,
        where: c.metric_registry_id == ^metric_id and c.change_trigger == "sync_apply",
        select: c.id
      )
      |> Repo.all()

    from(c in Changelog, where: c.id in ^ids) |> Repo.delete_all()

    ids
  end
end
