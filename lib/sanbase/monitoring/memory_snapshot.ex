defmodule Sanbase.Monitoring.MemorySnapshot do
  @moduledoc """
  Cheap, side-effect-free capture of BEAM/OS memory stats.

  Everything here is safe to run every minute on production pods: counter
  reads, one `/proc` file read, one pass over ETS tables and (opt-in) one
  pass over processes. Nothing forces GC and nothing enumerates per-process
  binary refs — the heavy diagnostics live in `Sanbase.Monitoring.MemDbg`
  and are console-only.

  Relative cost of what IS collected:

    * `:erlang.memory/0`, RSS, process/atom counts — counter reads, negligible.
    * `allocator_rows/0` — iterates allocator instances, sub-millisecond.
    * `top_ets/1` — one `:ets.info/2` pass over all tables (hundreds), cheap.
    * `process_groups/1` — `Process.info/2` on every process, including the
      `:dictionary` key (copies each pdict) so gen_servers group under their
      real `$initial_call` module instead of `:proc_lib.init_p/5`. O(process
      count) — the one moderately expensive call here, which is why the
      collector only requests it on every Nth sample.
  """

  @name_keys [:registered_name, :dictionary, :initial_call]
  @top_n 15

  @doc """
  Collect a snapshot as a plain map.

  Options:

    * `:include_process_groups` - also collect per-process-name memory
      groups (the O(process count) part). Default `false`.
    * `:top_n` - how many top ETS tables / process groups to keep.
  """
  @spec collect(Keyword.t()) :: map()
  def collect(opts \\ []) do
    top_n = Keyword.get(opts, :top_n, @top_n)
    start = System.monotonic_time(:millisecond)

    memory = Map.new(:erlang.memory())
    {alloc_used, alloc_allocated} = allocator_totals()
    proc_status = proc_status_bytes()

    process_groups =
      if Keyword.get(opts, :include_process_groups, false),
        do: process_groups(top_n),
        else: nil

    %{
      rss_bytes: proc_status.rss_bytes,
      rss_hwm_bytes: proc_status.rss_hwm_bytes,
      vm_total_bytes: memory[:total],
      vm_processes_bytes: memory[:processes],
      vm_binary_bytes: memory[:binary],
      vm_ets_bytes: memory[:ets],
      vm_code_bytes: memory[:code],
      alloc_used_bytes: alloc_used,
      alloc_allocated_bytes: alloc_allocated,
      process_count: length(Process.list()),
      atom_count: :erlang.system_info(:atom_count),
      top_ets: top_ets(top_n),
      process_groups: process_groups,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  @doc """
  VmRSS of the beam process from `/proc`. `nil` where /proc is unavailable
  (macOS dev) — callers must treat it as optional.
  """
  @spec rss_bytes() :: non_neg_integer() | nil
  def rss_bytes() do
    proc_status_bytes().rss_bytes
  end

  @doc """
  VmRSS (current) and VmHWM (peak since process start, never decreases) of
  the beam process from `/proc`. Both `nil` where /proc is unavailable
  (macOS dev). RSS converging toward an HWM set by an early spike is the
  carrier high-water ratchet, not a leak.
  """
  @spec proc_status_bytes() :: %{
          rss_bytes: non_neg_integer() | nil,
          rss_hwm_bytes: non_neg_integer() | nil
        }
  def proc_status_bytes() do
    case File.read("/proc/#{System.pid()}/status") do
      {:ok, content} ->
        %{
          rss_bytes: proc_status_kb_value(content, "VmRSS"),
          rss_hwm_bytes: proc_status_kb_value(content, "VmHWM")
        }

      _ ->
        %{rss_bytes: nil, rss_hwm_bytes: nil}
    end
  end

  defp proc_status_kb_value(content, name) do
    case Regex.run(~r/^#{name}:\s+(\d+) kB$/m, content) do
      [_, kb] -> String.to_integer(kb) * 1024
      _ -> nil
    end
  end

  @doc """
  Top `n` ETS tables by memory: `[%{name, memory_bytes, rows, owner}]`.
  """
  @spec top_ets(pos_integer()) :: [map()]
  def top_ets(n \\ @top_n) do
    word_size = :erlang.system_info(:wordsize)

    :ets.all()
    |> Enum.flat_map(fn table ->
      with mem when is_integer(mem) <- safe_ets_info(table, :memory),
           rows when is_integer(rows) <- safe_ets_info(table, :size) do
        [{table, mem * word_size, rows}]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(fn {_table, bytes, _rows} -> -bytes end)
    |> Enum.take(n)
    |> Enum.map(fn {table, bytes, rows} ->
      owner = safe_ets_info(table, :owner)
      owner_name = if is_pid(owner), do: proc_name(owner), else: inspect(owner)

      %{
        name: inspect(safe_ets_info(table, :name)),
        memory_bytes: bytes,
        rows: rows,
        owner: owner_name
      }
    end)
  end

  @doc """
  Top `n` process groups by total memory, grouped by process name:
  `[%{name, count, memory_bytes}]`. One process at 50 MB and ten thousand
  at 50 KB both show up here. O(process count), including `:dictionary`
  reads — do not call more often than every few minutes.
  """
  @spec process_groups(pos_integer()) :: [map()]
  def process_groups(n \\ @top_n) do
    Process.list()
    |> Enum.flat_map(fn pid ->
      case Process.info(pid, [:memory | @name_keys]) do
        nil -> []
        info -> [{name_from_info(info), info[:memory]}]
      end
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, bytes} -> bytes end)
    |> Enum.map(fn {name, sizes} ->
      %{name: name, count: length(sizes), memory_bytes: Enum.sum(sizes)}
    end)
    |> Enum.sort_by(& &1.memory_bytes, :desc)
    |> Enum.take(n)
  end

  @doc """
  Per-allocator `{name, used_bytes, allocated_bytes}` rows.

  `allocated` = carrier sizes (what the OS gave the VM, ~RSS),
  `used` = block sizes (what live Erlang data occupies, ~`:erlang.memory/0`).
  A big gap on eheap_alloc/binary_alloc = carriers ratcheted up by past
  spikes and/or fragmentation, not a leak.
  """
  @spec allocator_rows() :: [{atom(), non_neg_integer(), non_neg_integer()}]
  def allocator_rows() do
    for name <- :erlang.system_info(:alloc_util_allocators),
        instances = :erlang.system_info({:allocator_sizes, name}),
        is_list(instances) do
      {used, allocated} =
        Enum.reduce(instances, {0, 0}, fn
          {:instance, _n, props}, {used_acc, alloc_acc} ->
            sections =
              for key <- [:mbcs, :mbcs_pool, :sbcs],
                  {^key, section} <- [List.keyfind(props, key, 0)],
                  is_list(section),
                  do: section

            {
              used_acc + (sections |> Enum.map(&blocks_size/1) |> Enum.sum()),
              alloc_acc + (sections |> Enum.map(&carriers_size/1) |> Enum.sum())
            }

          _, acc ->
            acc
        end)

      {name, used, allocated}
    end
  rescue
    # allocator info format varies across OTP versions; stats must not crash
    _ -> []
  end

  @doc """
  BEAM boot time derived from wall clock uptime, truncated to the second.
  """
  @spec beam_started_at() :: DateTime.t()
  def beam_started_at() do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    (System.system_time(:millisecond) - uptime_ms)
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.truncate(:second)
  end

  @doc """
  Format a process name from `Process.info/2` results the way MemDbg does:
  registered name if set, otherwise `$initial_call`/`initial_call` MFA.
  """
  @spec name_from_info(Keyword.t()) :: String.t()
  def name_from_info(info) do
    case info[:registered_name] do
      name when is_atom(name) and name != nil ->
        inspect(name)

      _ ->
        fmt_mfa(info[:dictionary][:"$initial_call"] || info[:initial_call])
    end
  end

  @doc false
  def fmt_mfa({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
  def fmt_mfa(other), do: inspect(other)

  @doc false
  def proc_name(pid) do
    case Process.info(pid, @name_keys) do
      nil -> "<dead>"
      info -> name_from_info(info)
    end
  end

  @doc false
  def name_keys(), do: @name_keys

  defp allocator_totals() do
    case allocator_rows() do
      [] ->
        {nil, nil}

      rows ->
        {
          rows |> Enum.map(fn {_, used, _} -> used end) |> Enum.sum(),
          rows |> Enum.map(fn {_, _, allocated} -> allocated end) |> Enum.sum()
        }
    end
  end

  # blocks entry is either new-format {:blocks, [{alloc_name, [..., {:size, cur, ...}]}]}
  # or old-format {:blocks_size, cur, max, maxever}
  defp blocks_size(section) do
    case List.keyfind(section, :blocks, 0) do
      {:blocks, list} when is_list(list) ->
        Enum.reduce(list, 0, fn
          {_name, props}, acc when is_list(props) -> acc + tuple_size_value(props, :size)
          _, acc -> acc
        end)

      _ ->
        tuple_size_value(section, :blocks_size)
    end
  end

  defp carriers_size(section), do: tuple_size_value(section, :carriers_size)

  # values look like {:size, current} or {:size, current, max, maxever}
  defp tuple_size_value(props, key) do
    case List.keyfind(props, key, 0) do
      tuple when is_tuple(tuple) and tuple_size(tuple) >= 2 and is_integer(elem(tuple, 1)) ->
        elem(tuple, 1)

      _ ->
        0
    end
  end

  defp safe_ets_info(table, key) do
    :ets.info(table, key)
  rescue
    ArgumentError -> :undefined
  end
end
