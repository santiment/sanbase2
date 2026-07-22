defmodule SanbaseWeb.GenericAdmin.MemoryStat do
  @moduledoc """
  Read-only raw browsing of per-pod memory samples. The dashboard view with
  trends and details lives at /admin/memory_stats.
  """
  @behaviour SanbaseWeb.GenericAdmin

  def schema_module(), do: Sanbase.Monitoring.MemoryStat
  def resource_name(), do: "node_memory_stats"
  def singular_resource_name(), do: "node_memory_stat"

  def resource() do
    %{
      actions: [],
      index_fields: [
        :id,
        :pod_name,
        :container_type,
        :rss_bytes,
        :vm_total_bytes,
        :vm_processes_bytes,
        :vm_binary_bytes,
        :vm_ets_bytes,
        :process_count,
        :atom_count,
        :sample_duration_ms,
        :inserted_at
      ],
      preloads: [],
      belongs_to_fields: %{}
    }
  end
end
