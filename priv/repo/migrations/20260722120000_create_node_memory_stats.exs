defmodule Sanbase.Repo.Migrations.CreateNodeMemoryStats do
  use Ecto.Migration

  def change() do
    create table(:node_memory_stats) do
      add(:pod_name, :string, null: false)
      add(:container_type, :string, null: false)
      # BEAM boot time. A StatefulSet pod keeps its name across restarts, so
      # (pod_name, beam_started_at) is the true identity of one BEAM incarnation.
      add(:beam_started_at, :utc_datetime, null: false)

      # nil when /proc is not available (e.g. local macOS dev)
      add(:rss_bytes, :bigint)
      add(:vm_total_bytes, :bigint, null: false)
      add(:vm_processes_bytes, :bigint, null: false)
      add(:vm_binary_bytes, :bigint, null: false)
      add(:vm_ets_bytes, :bigint, null: false)
      add(:vm_code_bytes, :bigint, null: false)
      # allocator carriers (allocated) vs blocks (used); the gap is
      # high-water/fragmentation overhead invisible to :erlang.memory/0
      add(:alloc_used_bytes, :bigint)
      add(:alloc_allocated_bytes, :bigint)

      add(:process_count, :integer, null: false)
      add(:atom_count, :integer, null: false)
      add(:sample_duration_ms, :integer, null: false)

      # top-N ETS tables always; top-N process groups on every Nth sample
      add(:details, :map, null: false, default: %{})

      timestamps()
    end

    create(index(:node_memory_stats, [:pod_name, :inserted_at]))
    create(index(:node_memory_stats, [:inserted_at]))
  end
end
