defmodule SanbaseWeb.MetricRegistryController do
  use SanbaseWeb, :controller

  def sync(conn, %{"secret" => secret} = params) do
    case secret == get_sync_secret() do
      true ->
        try do
          case Sanbase.Metric.Registry.Sync.apply_sync(
                 Map.take(params, ["content", "confirmation_endpoint", "sync_uuid"])
               ) do
            :ok ->
              conn
              |> resp(200, "OK")
              |> send_resp()

            {:error, error} ->
              conn
              |> resp(500, "Error Syncing: #{inspect(error)}")
              |> send_resp()
          end
        rescue
          e ->
            conn
            |> resp(500, "Error syncing: #{Exception.message(e)}")
            |> send_resp()
        end

      false ->
        conn
        |> resp(403, "Unauthorized")
        |> send_resp()
    end
  end

  def mark_sync_as_completed(conn, %{
        "sync_uuid" => sync_uuid,
        "actual_changes" => actual_changes,
        "secret" => secret
      }) do
    case secret == get_sync_secret() do
      true ->
        case Sanbase.Metric.Registry.Sync.mark_sync_as_completed(sync_uuid, actual_changes) do
          {:ok, _} ->
            conn
            |> resp(200, "OK")
            |> send_resp()

          {:error, reason} ->
            conn
            |> resp(500, "Error marking sync as finished. Reason: #{reason}")
            |> send_resp()
        end

      false ->
        conn
        |> resp(403, "Unauthorized")
        |> send_resp()
    end
  end

  def export_json(conn, _params) do
    conn
    |> resp(200, get_metric_registry_json())
    |> send_resp()
  end

  defp get_metric_registry_json() do
    Sanbase.Metric.Registry.all()
    |> Enum.take(1)
    |> Enum.map(&transform/1)

    # |> Enum.map(&Jason.encode!/1)
    # |> Enum.intersperse("\n")
  end

  defp transform(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__, :inserted_at, :updated_at, :change_suggestions])
    |> Map.new(fn
      {k, v} when is_list(v) ->
        {k, Enum.map(v, &transform/1)}

      {k, v} when is_map(v) ->
        {k, transform(v)}

      {k, v} ->
        {k, v}
    end)
  end

  defp transform(data), do: data

  defp get_sync_secret() do
    Sanbase.Utils.Config.module_get(Sanbase.Metric.Registry.Sync, :sync_secret)
  end
end
