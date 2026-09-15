defmodule Sanbase.Billing.CreditPayments.SyncJob do
  @moduledoc ~s"""
  GenServer driving a manual re-import of credit payments from Stripe.

  One job at a time, held globally so the progress survives a LiveView remount, and
  broadcast over PubSub so any admin watching sees it. This is the button behind
  "the business thinks a month is missing": pick the range, run it again, and the
  upserts in `Sanbase.Billing.CreditPayments.Sync` repair whatever was skipped or
  classified by older code.

  Follows the same shape as `Sanbase.Billing.Invoices.GenerationJob`.
  """

  use GenServer

  alias Sanbase.Billing.CreditPayments.Sync

  @pubsub Sanbase.PubSub
  @topic "credit_payments_sync_job"

  @idle_state %{
    status: :idle,
    from_date: nil,
    to_date: nil,
    phase: nil,
    result: nil,
    error: nil,
    task_ref: nil
  }

  # ─── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe to job updates. The caller receives `{:sync_update, state}` messages."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "The current job state. Safe to call when the GenServer is not running."
  def get_state do
    case Process.whereis(__MODULE__) do
      nil -> @idle_state
      _pid -> GenServer.call(__MODULE__, :get_state)
    end
  end

  @doc "Start importing a range. Returns `:ok` or `{:error, :already_running}`."
  def start_job(%Date{} = from_date, %Date{} = to_date, user_id) do
    GenServer.call(__MODULE__, {:start_job, from_date, to_date, user_id})
  end

  @doc "Cancel the running import. Rows already written stay written."
  def cancel, do: GenServer.cast(__MODULE__, :cancel)

  # ─── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(_opts), do: {:ok, @idle_state}

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call(
        {:start_job, _from_date, _to_date, _user_id},
        _from,
        %{status: :running} = state
      ) do
    {:reply, {:error, :already_running}, state}
  end

  @impl true
  def handle_call({:start_job, from_date, to_date, user_id}, _from, prev) do
    job_pid = self()

    case Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
           do_sync(job_pid, from_date, to_date, user_id)
         end) do
      {:ok, task_pid} ->
        state = %{
          @idle_state
          | status: :running,
            from_date: from_date,
            to_date: to_date,
            phase: :fetching,
            task_ref: Process.monitor(task_pid)
        }

        broadcast(state)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, prev}
    end
  end

  @impl true
  def handle_cast(:cancel, %{status: :running, task_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    state = %{
      @idle_state
      | status: :cancelled,
        from_date: state.from_date,
        to_date: state.to_date
    }

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:cancel, state), do: {:noreply, state}

  @impl true
  def handle_info({:phase, phase}, %{status: :running} = state) do
    state = %{state | phase: phase}

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:phase, _phase}, state), do: {:noreply, state}

  @impl true
  def handle_info({:sync_done, result}, %{status: :running} = state) do
    if is_reference(state.task_ref), do: Process.demonitor(state.task_ref, [:flush])

    state = %{state | status: :done, phase: :done, result: result, task_ref: nil}

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:sync_failed, error}, %{status: :running} = state) do
    if is_reference(state.task_ref), do: Process.demonitor(state.task_ref, [:flush])

    state = %{state | status: :failed, phase: nil, error: error, task_ref: nil}

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    state = %{
      state
      | status: :failed,
        phase: nil,
        error: "The import process stopped: #{inspect(reason)}",
        task_ref: nil
    }

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  # ─── Worker ────────────────────────────────────────────────────────────────

  defp do_sync(job_pid, from_date, to_date, user_id) do
    result =
      Sync.sync_range(from_date, to_date,
        triggered_by: user_id,
        on_progress: fn {:phase, phase} -> send(job_pid, {:phase, phase}) end
      )

    case result do
      {:ok, summary} -> send(job_pid, {:sync_done, summary})
      {:error, error} -> send(job_pid, {:sync_failed, error})
    end
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:sync_update, state})
  end
end
