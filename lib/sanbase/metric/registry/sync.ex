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

  def by_uuid(uuid), do: Registry.SyncSchema.by_uuid(uuid)

  def cancel_run(uuid) do
    case Registry.SyncSchema.by_uuid(uuid) do
      {:ok, sync} ->
        case Registry.SyncSchema.update_status(sync, "cancelled", "Manually canceled") do
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
         {:ok, sync} <- store_sync_in_db(content),
         {:ok, sync} <- Registry.SyncSchema.update_status(sync, "executing"),
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
  def mark_sync_as_completed(sync_uuid) when is_binary(sync_uuid) do
    Logger.info("Marking Metric Registry sync as finished for UUID #{sync_uuid}")

    with {:ok, sync} <- Registry.SyncSchema.by_uuid(sync_uuid),
         {:ok, list} <- extract_metric_registry_list(sync),
         :ok <- mark_metric_registries_as_synced(list),
         {:ok, sync} <- Registry.SyncSchema.update_status(sync, "completed") do
      SanbaseWeb.Endpoint.broadcast_from(self(), @pubsub_topic, "sync_completed", %{})
      {:ok, sync}
    end
  end

  def apply_sync(params) do
    Logger.info("Applying Metric Registry sync")

    with :ok <- check_apply_env(),
         {:ok, list} when is_list(list) <- Jason.decode(params["content"]),
         {:ok, _actual_change} <- do_apply_sync_content(list),
         {:ok, _} <- send_sync_completed_confirmation(params["confirmation_endpoint"]) do
      :ok
    end
  end

  def last_syncs(limit) do
    Registry.SyncSchema.last_syncs(limit)
  end

  # Private functions

  defp send_sync_completed_confirmation(url) do
    Logger.info("Confirming that a Metric Registry sync was completed to url #{url}")

    Req.post(url)
  end

  defp do_apply_sync_content(list) do
    list
    |> Enum.reduce(Ecto.Multi.new(), fn params, multi ->
      multi_metric_registry_update(multi, params)
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{} = _map} -> :ok
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  defp multi_metric_registry_update(multi, params) do
    params = Map.put(params, "sync_status", "synced")

    %{"metric" => metric, "data_type" => data_type, "fixed_parameters" => fixed_parameters} =
      params

    with {:ok, metric_registry} <- Registry.by_name(metric, data_type, fixed_parameters) do
      changeset = Registry.changeset(metric_registry, params)
      Ecto.Multi.update(multi, metric_registry.id, changeset)
    end
  end

  defp no_running_syncs() do
    case Registry.SyncSchema.all_with_status("executing") do
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
        {:ok, _} = Registry.SyncSchema.update_status(sync, "failed", error)
        {:error, error}

      {:error, reason} ->
        error = inspect(reason)
        {:ok, _} = Registry.SyncSchema.update_status(sync, "failed", error)
        {:error, "Failed to sync, error: #{error}"}
    end
  end

  defp mark_metric_registries_as_synced(list) do
    Enum.reduce_while(list, :ok, fn map, _acc ->
      with {:ok, metric} <-
             Registry.by_name(
               Map.fetch!(map, "metric"),
               Map.fetch!(map, "data_type"),
               Map.fetch!(map, "fixed_parameters")
             ),
           {:ok, _metric} <- Registry.update(metric, %{"sync_status" => "synced"}) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp store_sync_in_db(content) do
    Registry.SyncSchema.create(content)
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
      [] -> {:error, "Nothing to sync"}
      structs -> {:ok, Jason.encode!(structs)}
    end
  end

  defp check_initiate_env() do
    deployment_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
    database_url = System.get_env("DATABASE_URL")

    # If local, the DATABASE_URL should not be set pointing to stage/prod.
    # Only work if the local postgres is used
    local? = deployment_env in ["dev", "test"] and is_nil(database_url)
    stage? = deployment_env == "stage"

    if local? or stage? do
      :ok
    else
      {:error, "Can only deploy sync from STAGE to PROD"}
    end
  end

  defp check_apply_env() do
    deployment_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
    database_url = System.get_env("DATABASE_URL")

    # If local, the DATABASE_URL should not be set pointing to stage/prod.
    # Only work if the local postgres is used
    local? = deployment_env in ["dev", "test"] and is_nil(database_url)
    prod? = deployment_env == "prod"

    if local? or prod? do
      :ok
    else
      {:error, "Can apply sync only on PROD"}
    end
  end

  defp extract_metric_registry_list(sync) do
    sync.content
    |> Jason.decode()
  end

  defp get_confirmation_endpoint(sync) do
    secret = Sanbase.Utils.Config.module_get(Sanbase.Metric.Registry.Sync, :sync_secret)

    SanbaseWeb.Endpoint.backend_url()
    |> URI.parse()
    |> URI.append_path("/mark_metric_registry_sync_as_finished/#{sync.uuid}?secret=#{secret}")
    |> URI.to_string()
  end
end
