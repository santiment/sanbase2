defmodule SanbaseWeb.MetricRegistryController do
  use SanbaseWeb, :controller

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
end
