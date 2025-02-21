defmodule Sanbase.Metric.Registry.Sync do
  @moduledoc """
  This module is responsible for syncing the metric registry with the external
  source of truth.
  """

  alias Hex.Solver.Registry
  alias Sanbase.Metric.Registry
  alias Sanbase.Utils.Config

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]
  require Logger

  @pubsub_topic "sanbase_metric_registry_sync"

  def by_uuid(uuid) do
    Registry.SyncRun.by_uuid(uuid)
  end

  def cancel_run(uuid) do
    case Registry.SyncRun.by_uuid(uuid) do
      {:ok, sync} ->
        case Registry.SyncRun.update_status(sync, "cancelled", "Manually canceled") do
          {:ok, sync} ->
            {:ok, sync}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, "Failed to cancel the sync. Error: #{changeset_errors_string(changeset)}"}
        end

      {:error, _} ->
        {:error, "Sync not found"}
    end
  end

  @doc ~s"""
  Start a sync that will sync the not synced metrics from stage to prod
  """
  @spec sync(list(non_neg_integer())) :: :ok
  def sync(metric_registry_ids) when is_list(metric_registry_ids) do
    Logger.info("Initiating sync for #{length(metric_registry_ids)} metric registry records")

    with :ok <- no_running_syncs(),
         :ok <- check_initiate_env(),
         {:ok, content} <- get_sync_content(metric_registry_ids),
         {:ok, sync} <- store_initial_sync_in_db(content),
         {:ok, sync} <- Registry.SyncRun.update_status(sync, "executing"),
         :ok <- start_sync(sync) do
      SanbaseWeb.Endpoint.broadcast_from(self(), @pubsub_topic, "sync_started", %{})
      {:ok, sync}
    end
  end

  @doc ~s"""
  When the sync application on prod is completed, it sends a HTTP POST request
  back to the initiator that the sync is finished. The initiator calls this function
  to mark the sync as completed.
  """
  def mark_sync_as_completed(sync_uuid, actual_changes) when is_binary(sync_uuid) do
    Logger.info("Marking Metric Registry sync as finished for UUID #{sync_uuid}")

    with {:ok, decoded_changes} <- decode_changes(actual_changes),
         {:ok, sync} <- Registry.SyncRun.by_uuid(sync_uuid),
         {:ok, list} <- extract_metric_registry_identifiers_list(decoded_changes),
         :ok <- mark_metric_registries_as_synced(list),
         {:ok, sync} <-
           Registry.SyncRun.update(sync, %{status: "completed", actual_changes: actual_changes}) do
      SanbaseWeb.Endpoint.broadcast_from(self(), @pubsub_topic, "sync_completed", %{})

      {:ok, sync}
    end
  end

  def apply_sync(%{
        "content" => content,
        "confirmation_endpoint" => confirmation_endpoint,
        "sync_uuid" => sync_uuid
      }) do
    Logger.info("Applying Metric Registry sync")

    with :ok <- check_apply_env(),
         {:ok, list} when is_list(list) <- Jason.decode(content),
         {:ok, changesets} <- do_apply_sync_content(list),
         {:ok, actual_changes} <- generate_actual_changes_applied(changesets),
         {:ok, _} <- send_sync_completed_confirmation(confirmation_endpoint, actual_changes),
         {:ok, _sync} <- store_applied_sync_in_db(content, sync_uuid) do
      :ok
    end
  end

  def last_syncs(limit) do
    Registry.SyncRun.last_syncs(limit)
  end

  def actual_changes_formatted(%Registry.SyncRun{actual_changes: nil}), do: ""

  def actual_changes_formatted(%Registry.SyncRun{actual_changes: actual_changes}) do
    with {:ok, decoded} <- decode_changes(actual_changes) do
      decoded
      # Has the form {key, change}
      |> Enum.map(fn {key, changes} ->
        formatted_patch = Sanbase.ExAudit.Patch.format_patch(%{patch: changes})

        ["Metric ", key.metric, " ", formatted_patch]
      end)
    end
  end

  def encode_changes(changes) do
    changes
    |> :erlang.term_to_binary()
    |> :zlib.gzip()
    |> Base.encode64()
  end

  def decode_changes(bin) do
    with {:ok, decoded} <- bin |> Base.decode64() do
      result =
        decoded
        |> :zlib.gunzip()
        |> :erlang.binary_to_term()

      {:ok, result}
    end
  end

  # Private functions
  defp generate_actual_changes_applied(changesets) when is_list(changesets) do
    changes =
      Enum.map(changesets, fn changeset ->
        old = changeset.data
        new = changeset |> Ecto.Changeset.apply_changes()

        key = Map.take(changeset.data, [:metric, :data_type, :fixed_parameters])
        {key, ExAudit.Diff.diff(old, new)}
      end)

    {:ok, changes}
  end

  defp send_sync_completed_confirmation(url, changes) do
    # The URL already contains the sync uuid and the secret token
    Logger.info("Confirming that a Metric Registry sync was completed to url #{url}")

    Req.post(url, json: %{actual_changes: encode_changes(changes)})
  end

  defp do_apply_sync_content(list) do
    {multi, changesets} =
      list
      |> Enum.reduce({Ecto.Multi.new(), []}, fn params, {multi, changesets} ->
        %{"metric" => metric, "data_type" => data_type, "fixed_parameters" => fixed_parameters} =
          params

        case Registry.by_name(metric, data_type, fixed_parameters) do
          # Update existing metric
          {:ok, metric_registry} ->
            # Working directly with changesets allow to manually put sync_status
            # Using the update/create functions do not allow manually setting it
            params = Map.merge(params, Registry.mark_as_synced_params())
            registry_changeset = Registry.changeset(metric_registry, params)

            changelog_changeset =
              Registry.Changelog.create_changeset(registry_changeset,
                change_trigger: "sync_apply"
              )

            # Update the Registry Record with the changed
            # Insert a record in the Registry.Changelog
            updated_multi =
              Ecto.Multi.update(multi, metric_registry.id, registry_changeset)
              |> Ecto.Multi.insert(
                {:metric_registry_changelog, metric_registry.id},
                changelog_changeset
              )

            # Insert a record in the Registry Changelong, recording the state before and after

            {updated_multi, [registry_changeset | changesets]}

          # There is no such metric. This is creating a new metric
          {:error, _} ->
            # Working directly with changesets allow to manually put sync_status
            # Using the update/create functions do not allow manually setting it
            params = Map.merge(params, Registry.mark_as_synced_params())
            registry_changeset = Registry.changeset(%Registry{}, params)

            updated_multi =
              Ecto.Multi.insert(
                multi,
                {:metric_registry_insert, metric, data_type, fixed_parameters},
                registry_changeset
              )

            {updated_multi, [registry_changeset | changesets]}
        end
      end)

    case Sanbase.Repo.transaction(multi) do
      {:ok, _map} -> {:ok, changesets}
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  defp no_running_syncs() do
    case Registry.SyncRun.all_with_status("executing") do
      [] -> :ok
      [_ | _] -> {:error, "Sync process is already running"}
    end
  end

  defp start_sync(sync) do
    url = get_sync_target_url()

    json = %{
      "sync_uuid" => sync.uuid,
      "content" => sync.content,
      "generated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "confirmation_endpoint" => get_confirmation_endpoint(sync)
    }

    case Req.post(url, json: json) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        error = "Failed to sync, received status code: #{status}. Body: #{body}"
        {:ok, _} = Registry.SyncRun.update_status(sync, "failed", error)
        {:error, error}

      {:error, reason} ->
        error = inspect(reason)
        {:ok, _} = Registry.SyncRun.update_status(sync, "failed", error)
        {:error, "Failed to sync, error: #{error}"}
    end
  end

  defp mark_metric_registries_as_synced(list) do
    Enum.reduce_while(list, :ok, fn map, _acc ->
      with {:ok, metric} <-
             Registry.by_name(
               map.metric,
               map.data_type,
               map.fixed_parameters
             ),
           {:ok, _metric} <- Registry.mark_as_synced(metric) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp store_initial_sync_in_db(content) do
    attrs = %{
      content: content,
      sync_type: "outgoing",
      status: "scheduled",
      uuid: Ecto.UUID.generate()
    }

    Registry.SyncRun.create(attrs)
  end

  defp store_applied_sync_in_db(content, uuid) do
    attrs = %{
      content: content,
      sync_type: "incoming",
      status: "completed",
      uuid: uuid
    }

    Registry.SyncRun.create(attrs)
  end

  defp get_sync_target_url() do
    secret = Config.module_get(Sanbase.Metric.Registry.Sync, :sync_secret)
    deployment_env = Config.module_get(Sanbase, :deployment_env)
    port = Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    case deployment_env do
      "dev" -> "http://localhost:#{port}/sync_metric_registry?secret=#{secret}"
      "prod" -> raise("Cannot initiate sync from PROD")
      "stage" -> "https://api.santiment.net/sync_metric_registry?secret=#{secret}"
    end
  end

  defp get_sync_content([]), do: {:error, "Nothing to sync"}

  defp get_sync_content(metric_registry_ids) do
    case Sanbase.Metric.Registry.by_ids(metric_registry_ids) do
      [] ->
        {:error, "Nothing to sync"}

      structs ->
        {:ok, Jason.encode!(structs)}
    end
  end

  defp check_initiate_env() do
    deployment_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
    database_url = System.get_env("DATABASE_URL")

    # If local, the DATABASE_URL should not be set pointing to stage/prod.
    # The URL can be nil or when running in CI it points to a URL that is not amazon RDS
    local? =
      deployment_env in ["dev", "test"] and
        (is_nil(database_url) or not String.contains?(database_url, ["amazon", "aws"]))

    stage? = deployment_env == "stage"

    if local? or stage? do
      :ok
    else
      {:error,
       "Can only deploy sync from STAGE to PROD. Attempted to deploy from #{deployment_env}"}
    end
  end

  defp check_apply_env() do
    deployment_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
    database_url = System.get_env("DATABASE_URL")

    # If local, the DATABASE_URL should not be set pointing to stage/prod.
    # The URL can be nil or when running in CI it points to a URL that is not amazon RDS
    local? =
      deployment_env in ["dev", "test"] and
        (is_nil(database_url) or not String.contains?(database_url, ["amazon", "aws"]))

    prod? = deployment_env == "prod"

    if local? or prod? do
      :ok
    else
      {:error, "Can apply sync only on PROD"}
    end
  end

  defp extract_metric_registry_identifiers_list(actual_changes) do
    keys =
      actual_changes
      |> Enum.map(fn {%{metric: _, data_type: _, fixed_parameters: _} = key, _changes} -> key end)

    {:ok, keys}
  end

  defp get_confirmation_endpoint(sync) do
    secret = Sanbase.Utils.Config.module_get(Sanbase.Metric.Registry.Sync, :sync_secret)

    SanbaseWeb.Endpoint.backend_url()
    |> URI.parse()
    |> URI.append_path("/mark_metric_registry_sync_as_finished/#{sync.uuid}?secret=#{secret}")
    |> URI.to_string()
  end
end
