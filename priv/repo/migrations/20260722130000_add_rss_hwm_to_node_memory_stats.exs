defmodule Sanbase.Repo.Migrations.AddRssHwmToNodeMemoryStats do
  use Ecto.Migration

  def change() do
    alter table(:node_memory_stats) do
      # VmHWM from /proc — peak RSS since BEAM start, never decreases.
      # RSS creeping toward an early-spike HWM = carrier ratchet, not a leak.
      add(:rss_hwm_bytes, :bigint)
    end
  end
end
