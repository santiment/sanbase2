defmodule Sanbase.Billing.Invoices.GenerationJob do
  @moduledoc """
  GenServer that manages invoice archive generation.

  Holds a single global job state (one job at a time), so progress survives
  LiveView navigation. Any LiveView can subscribe to PubSub updates and
  reconnect to a running job when remounting.

  Follows the same pattern as Sanbase.AI.DescriptionJob.
  """

  use GenServer

  alias Sanbase.Billing.Invoices.{Download, InvoiceArchive, S3Storage}

  @pubsub Sanbase.PubSub
  @topic "invoice_generation_job"

  @idle_state %{
    status: :idle,
    year: nil,
    month: nil,
    total: 0,
    done: 0,
    failed: 0,
    errors: [],
    task_ref: nil,
    phase: nil
  }

  # ─── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe to PubSub job updates. Caller receives `{:job_update, state}` messages."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "Returns current job state. Safe to call when GenServer is not started."
  def get_state do
    case Process.whereis(__MODULE__) do
      nil -> @idle_state
      _pid -> GenServer.call(__MODULE__, :get_state)
    end
  end

  @doc "Start a new generation job. Returns `:ok` or `{:error, :already_running}`."
  def start_job(year, month, user_id) do
    GenServer.call(__MODULE__, {:start_job, year, month, user_id})
  end

  @doc "Cancel the running job."
  def cancel, do: GenServer.cast(__MODULE__, :cancel)

  # ─── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(_opts), do: {:ok, @idle_state}

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call(:running?, _from, state), do: {:reply, state.status == :running, state}

  @impl true
  def handle_call({:start_job, _, _, _}, _from, %{status: :running} = state) do
    {:reply, {:error, :already_running}, state}
  end

  @impl true
  def handle_call({:start_job, year, month, user_id}, _from, _prev) do
    gen_pid = self()

    # Create or update the DB record to "generating"
    {:ok, archive} =
      InvoiceArchive.create_or_update(%{
        year: year,
        month: month,
        status: "generating",
        generated_by: user_id,
        error_message: nil
      })

    {:ok, task_pid} =
      Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
        do_generate(gen_pid, archive, year, month)
      end)

    task_ref = Process.monitor(task_pid)

    new_state = %{
      status: :running,
      year: year,
      month: month,
      total: 0,
      done: 0,
      failed: 0,
      errors: [],
      task_ref: task_ref,
      phase: :fetching_invoices
    }

    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:cancel, state) do
    # Mark archive as failed when cancelled
    if state.year && state.month do
      case InvoiceArchive.get_by_month(state.year, state.month) do
        nil -> :ok
        archive -> InvoiceArchive.mark_failed(archive, "Cancelled by user")
      end
    end

    new_state = %{state | status: :cancelled, task_ref: nil, phase: nil}
    broadcast(new_state)
    {:noreply, new_state}
  end

  # Ignore item results after cancellation / completion
  @impl true
  def handle_info({:item_done, _, _}, %{status: s} = state) when s != :running do
    {:noreply, state}
  end

  @impl true
  def handle_info({:item_done, :ok, _index}, state) do
    new_state = %{state | done: state.done + 1, phase: :downloading_pdfs}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:item_done, {:error, reason}, _index}, state) do
    new_state = %{
      state
      | failed: state.failed + 1,
        errors: [inspect(reason) | state.errors],
        phase: :downloading_pdfs
    }

    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:set_total, total}, state) do
    new_state = %{state | total: total, phase: :downloading_pdfs}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:set_phase, phase}, state) do
    new_state = %{state | phase: phase}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:job_finished, %{status: :running} = state) do
    new_state = %{state | status: :done, task_ref: nil, phase: :done}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:job_finished, state), do: {:noreply, state}

  @impl true
  def handle_info({:job_failed, reason}, %{status: :running} = state) do
    new_state = %{
      state
      | status: :failed,
        task_ref: nil,
        phase: nil,
        errors: [reason | state.errors]
    }

    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:job_failed, _reason}, state), do: {:noreply, state}

  # Worker task crashed before sending :job_finished
  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{task_ref: ref, status: :running} = state
      ) do
    # Mark archive as failed
    if state.year && state.month do
      case InvoiceArchive.get_by_month(state.year, state.month) do
        nil -> :ok
        archive -> InvoiceArchive.mark_failed(archive, "Worker process crashed")
      end
    end

    new_state = %{state | status: :failed, task_ref: nil, phase: nil}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _, _}, state), do: {:noreply, state}

  # ─── Private ──────────────────────────────────────────────────────────────

  defp do_generate(gen_pid, archive, year, month) do
    try do
      # Phase 1: Fetch invoice list from Stripe
      send(gen_pid, {:set_phase, :fetching_invoices})
      invoices = Download.fetch_paid_invoices(year, month)
      send(gen_pid, {:set_total, length(invoices)})

      if invoices == [] do
        InvoiceArchive.mark_failed(archive, "No paid invoices found for this month")
        send(gen_pid, {:job_failed, "No paid invoices found for this month"})
        return_early()
      end

      # Phase 2: Download each PDF
      pdf_entries =
        invoices
        |> Enum.with_index()
        |> Enum.reduce([], fn {invoice, index}, acc ->
          if GenServer.call(gen_pid, :running?) do
            case Download.download_pdf(invoice) do
              {:ok, entry} ->
                send(gen_pid, {:item_done, :ok, index})
                [entry | acc]

              {:error, reason} ->
                send(gen_pid, {:item_done, {:error, reason}, index})
                acc
            end
          else
            acc
          end
        end)
        |> Enum.reverse()

      # Check if still running (might have been cancelled)
      unless GenServer.call(gen_pid, :running?) do
        return_early()
      end

      if pdf_entries == [] do
        InvoiceArchive.mark_failed(archive, "All PDF downloads failed")
        send(gen_pid, {:job_failed, "All PDF downloads failed"})
        return_early()
      end

      # Phase 3: Create ZIP
      send(gen_pid, {:set_phase, :creating_zip})

      {:ok, {_zip_name, zip_binary}} =
        Download.create_zip_in_memory(pdf_entries, "#{year}_#{month}.zip")

      # Phase 4: Upload to S3
      send(gen_pid, {:set_phase, :uploading_s3})

      case S3Storage.upload_zip(zip_binary, year, month) do
        {:ok, s3_key} ->
          total_amount = Enum.reduce(invoices, 0, fn inv, acc -> acc + (inv[:total] || 0) end)

          InvoiceArchive.mark_completed(archive, %{
            s3_key: s3_key,
            invoice_count: length(pdf_entries),
            total_amount: total_amount,
            file_size: byte_size(zip_binary)
          })

        {:error, reason} ->
          InvoiceArchive.mark_failed(archive, "S3 upload failed: #{inspect(reason)}")
          send(gen_pid, {:job_failed, "S3 upload failed: #{inspect(reason)}"})
          return_early()
      end

      send(gen_pid, :job_finished)
    rescue
      e ->
        InvoiceArchive.mark_failed(archive, Exception.message(e))
        send(gen_pid, {:job_failed, Exception.message(e)})
    catch
      :throw, :return_early -> :ok
    end
  end

  defp return_early, do: throw(:return_early)

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:job_update, state})
  end
end
