defmodule Sanbase.Metric.Registry.Drift do
  @moduledoc """
  Detect drift between the metric registry on stage and on prod.

  The regular sync only pushes explicitly selected records from stage to prod,
  so it cannot detect changes introduced outside of it:
  - manual DB interventions on either environment;
  - deletions on stage, which are never propagated to prod;
  - renames on stage (changes to metric/data_type/fixed_parameters), which are
    applied on prod as an INSERT of a new record, leaving the record with the
    old name orphaned on prod.

  This module fetches the full metric registry export from prod and compares
  it against the local (stage) registry, keyed by (metric, data_type,
  fixed_parameters). Only fields that are subject to syncing are compared
  (the fields included in the Registry Jason.Encoder), so env-local fields
  like id, is_verified, sync_status and last_sync_datetime do not produce
  false positives.

  The check is strictly read-only and side-effect free: it performs only
  SELECTs on the local database and a GET request for the prod export. It
  writes nothing, emits no events and can be run any number of times. The
  only environment restriction is that it cannot run on prod itself, where
  it would compare prod against its own export.
  """

  alias Sanbase.Metric.Registry
  alias Sanbase.Utils.Config

  @receive_timeout 60_000

  @type key :: %{metric: String.t(), data_type: String.t(), fixed_parameters: map()}

  @type result :: %{
          checked_at: DateTime.t(),
          local_count: non_neg_integer(),
          remote_count: non_neg_integer(),
          identical_count: non_neg_integer(),
          missing_on_prod: [map()],
          extra_on_prod: [map()],
          changed: [map()]
        }

  @doc ~s"""
  Compare the local (stage) metric registry with the prod one.

  Returns a map with three lists of drift entries:
  - missing_on_prod -- records that exist locally but not on prod. Expected
    (pending_sync?: true) if the record is not yet synced, alarming otherwise;
  - extra_on_prod -- records that exist only on prod. The sync never deletes,
    so these are orphans left by renames/deletions on stage or records
    manually created on prod;
  - changed -- records that exist on both sides but differ in their synced
    fields. Expected (pending_sync?: true) if the record has local changes
    that are not yet synced, alarming otherwise.
  """
  @spec compute() :: {:ok, result()} | {:error, String.t()}
  def compute() do
    with {:ok, url} <- get_export_url(),
         {:ok, remote_entries} <- fetch_remote_entries(url) do
      {:ok, compare(local_entries(), remote_entries)}
    end
  end

  @spec no_drift?(result()) :: boolean()
  def no_drift?(result) do
    result.missing_on_prod == [] and result.extra_on_prod == [] and result.changed == []
  end

  # Private functions

  defp compare(local_entries, remote_entries) do
    local_by_key = Map.new(local_entries, &{&1.key, &1})
    remote_by_key = Map.new(remote_entries, &{&1.key, &1})

    local_keys = local_by_key |> Map.keys() |> MapSet.new()
    remote_keys = remote_by_key |> Map.keys() |> MapSet.new()
    common_keys = MapSet.intersection(local_keys, remote_keys)

    missing_on_prod =
      MapSet.difference(local_keys, remote_keys)
      |> Enum.map(fn key ->
        local = local_by_key[key]

        %{
          key: key,
          id: local.id,
          sync_status: local.sync_status,
          pending_sync?: local.sync_status == "not_synced"
        }
      end)
      |> sort_by_metric()

    extra_on_prod =
      MapSet.difference(remote_keys, local_keys)
      |> Enum.map(fn key -> %{key: key} end)
      |> sort_by_metric()

    changed =
      common_keys
      |> Enum.reduce([], fn key, acc ->
        local = local_by_key[key]
        remote = remote_by_key[key]

        # Diff with prod as the old state and stage as the new state, so the
        # patch reads as "what needs to change on prod to match stage"
        case ExAudit.Diff.diff(remote.content, local.content) do
          :not_changed ->
            acc

          diff when is_map(diff) ->
            entry = %{
              key: key,
              id: local.id,
              sync_status: local.sync_status,
              pending_sync?: local.sync_status == "not_synced",
              diff: diff
            }

            [entry | acc]
        end
      end)
      |> sort_by_metric()

    %{
      checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      local_count: length(local_entries),
      remote_count: length(remote_entries),
      identical_count: MapSet.size(common_keys) - length(changed),
      missing_on_prod: missing_on_prod,
      extra_on_prod: extra_on_prod,
      changed: changed
    }
  end

  defp sort_by_metric(list), do: Enum.sort_by(list, & &1.key.metric)

  defp local_entries() do
    Registry.all()
    |> Enum.map(fn %Registry{} = registry ->
      content = Registry.to_synced_map(registry)

      %{
        key: Registry.identity_key(content),
        id: registry.id,
        sync_status: registry.sync_status,
        content: content
      }
    end)
  end

  defp fetch_remote_entries(url) do
    case Req.get(url, receive_timeout: @receive_timeout) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        parse_ndjson_export(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         "Failed to fetch the prod metric registry export. Status code: #{status}. Body: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch the prod metric registry export. Error: #{inspect(reason)}"}
    end
  end

  defp parse_ndjson_export(body) do
    # The export also contains env-local fields like id and sync_status.
    # Keep only the synced fields, so the comparison matches the local
    # content and additions to the schema don't need updates here.
    synced_field_names = Registry.synced_field_names()

    entries =
      body
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        content =
          line
          |> Jason.decode!()
          |> Map.take(synced_field_names)
          |> normalize_content()

        %{key: Registry.identity_key(content), content: content}
      end)

    {:ok, entries}
  rescue
    e ->
      {:error, "Failed to decode the prod metric registry export. Error: #{Exception.message(e)}"}
  end

  # Normalizes only top-level values on purpose: the only DateTime field in
  # the schema (hard_deprecate_after) is top-level; none of the embeds
  # contain calendar types.
  defp normalize_content(content) when is_map(content) do
    Map.new(content, fn {key, value} -> {key, normalize_value(value)} end)
  end

  # Older versions of the export endpoint exploded DateTime structs into maps
  # instead of encoding them as ISO8601 strings. Convert them back to ISO8601
  # so they don't produce false positives until prod serves the fixed export.
  defp normalize_value(%{
         "calendar" => "Elixir.Calendar.ISO",
         "year" => year,
         "month" => month,
         "day" => day,
         "hour" => hour,
         "minute" => minute,
         "second" => second
       }) do
    DateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, second), "Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp normalize_value(value), do: value

  # The drift check is read-only, so unlike the sync it does not need any
  # environment write-safety guards. The only restriction is that it cannot
  # run on prod itself -- there it would compare prod against its own export.
  # The export secret is expected to have the same value on stage and prod,
  # the same way the sync secret does.
  defp get_export_url() do
    secret = Config.module_get(Sanbase.Metric.Registry.Sync, :export_secret)
    deployment_env = Config.module_get(Sanbase, :deployment_env)
    port = Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    case deployment_env do
      "prod" ->
        {:error,
         "The drift check compares the local registry against the prod one, " <>
           "so it cannot be run on prod itself"}

      "stage" ->
        {:ok, "https://api.santiment.net/metric_registry_export?secret=#{secret}"}

      env when env in ["dev", "test"] ->
        {:ok, "http://localhost:#{port}/metric_registry_export?secret=#{secret}"}
    end
  end
end
