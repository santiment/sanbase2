defmodule Sanbase.Cache.RehydratingCache.Progress do
  @moduledoc ~s"""
  The per-key computation state tracked by `Sanbase.Cache.RehydratingCache`.

  Every registered function is, at any point, in exactly one of these states:

    * `:running`   - a task is currently computing the value. `pid` is that
      task and `started_unix` is when it started (unix seconds; a human-readable
      time is `DateTime.from_unix!(started_unix)` when inspecting state).
    * `:scheduled` - not running; the next run is due at/after `run_after_unix`
      (unix seconds). A timestamp in the past means "due now".
    * `:failed`    - the last computation crashed; it is retried on the next run.
    * `:paused`    - refreshing is paused because the key has not been read
      recently; the next read resumes it (see `RehydratingCache.put_last_access/2`).

  Use the constructors below rather than building the struct by hand so the
  invariants of each status stay in one place.
  """

  @enforce_keys [:status]
  defstruct [:status, :pid, :started_unix, :run_after_unix]

  @type status :: :running | :scheduled | :failed | :paused

  @type t :: %__MODULE__{
          status: status(),
          pid: pid() | nil,
          started_unix: non_neg_integer() | nil,
          run_after_unix: non_neg_integer() | nil
        }

  @doc "A task is currently computing the value; `started_unix` is when it started."
  @spec running(pid(), non_neg_integer()) :: t()
  def running(pid, started_unix) do
    %__MODULE__{status: :running, pid: pid, started_unix: started_unix}
  end

  @doc "Not running; the next run is due at/after `run_after_unix` (unix seconds)."
  @spec scheduled(non_neg_integer()) :: t()
  def scheduled(run_after_unix) do
    %__MODULE__{status: :scheduled, run_after_unix: run_after_unix}
  end

  @doc "The last computation crashed; retry on the next run."
  @spec failed() :: t()
  def failed(), do: %__MODULE__{status: :failed}

  @doc "Refreshing is paused because the key is unread; a read resumes it."
  @spec paused() :: t()
  def paused(), do: %__MODULE__{status: :paused}
end
