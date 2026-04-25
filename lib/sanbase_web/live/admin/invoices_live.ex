defmodule SanbaseWeb.Admin.InvoicesLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Billing.Invoices.{InvoiceArchive, GenerationJob, S3Storage}
  # S3Storage used in delete/regenerate events

  @start_year 2020

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    if connected?(socket), do: GenerationJob.subscribe()

    job_state = GenerationJob.get_state()
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:page_title, "Invoice Archives")
      |> assign(:archives, InvoiceArchive.list_all())
      |> assign(:selected_year, now.year)
      |> assign(:selected_month, now.month)
      |> assign(:years, @start_year..now.year |> Enum.to_list() |> Enum.reverse())
      |> assign(:job, if(job_state.status == :idle, do: nil, else: job_state))
      |> assign(:confirm_action, nil)
      |> assign(:confirm_archive_id, nil)
      |> assign(:flash_error, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("select_period", %{"year" => year, "month" => month}, socket) do
    {:noreply,
     socket
     |> assign(:selected_year, String.to_integer(year))
     |> assign(:selected_month, String.to_integer(month))}
  end

  def handle_event("generate", %{"year" => year, "month" => month}, socket) do
    year = String.to_integer(year)
    month = String.to_integer(month)
    user_id = socket.assigns.current_user.id

    case GenerationJob.start_job(year, month, user_id) do
      :ok ->
        {:noreply, socket |> assign(:selected_year, year) |> assign(:selected_month, month)}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A generation job is already running")}
    end
  end

  def handle_event("cancel", _params, socket) do
    GenerationJob.cancel()
    {:noreply, socket}
  end

  def handle_event("download", %{"id" => id}, socket) do
    {:noreply, redirect(socket, to: ~p"/admin/invoices/download/#{id}")}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirm_action: :delete, confirm_archive_id: String.to_integer(id))}
  end

  def handle_event("confirm_regenerate", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, confirm_action: :regenerate, confirm_archive_id: String.to_integer(id))}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, confirm_action: nil, confirm_archive_id: nil)}
  end

  def handle_event("delete", _params, socket) do
    archive = Enum.find(socket.assigns.archives, &(&1.id == socket.assigns.confirm_archive_id))

    if archive do
      if archive.s3_key, do: S3Storage.delete_zip(archive.s3_key)
      InvoiceArchive.delete!(archive)
    end

    {:noreply,
     socket
     |> assign(:archives, InvoiceArchive.list_all())
     |> assign(confirm_action: nil, confirm_archive_id: nil)}
  end

  def handle_event("regenerate", _params, socket) do
    archive = Enum.find(socket.assigns.archives, &(&1.id == socket.assigns.confirm_archive_id))

    socket = assign(socket, confirm_action: nil, confirm_archive_id: nil)

    if archive do
      if archive.s3_key, do: S3Storage.delete_zip(archive.s3_key)
      user_id = socket.assigns.current_user.id

      case GenerationJob.start_job(archive.year, archive.month, user_id) do
        :ok ->
          {:noreply, socket}

        {:error, :already_running} ->
          {:noreply, put_flash(socket, :error, "A job is already running")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset_stale", %{"id" => id}, socket) do
    archive = Enum.find(socket.assigns.archives, &(&1.id == String.to_integer(id)))

    if archive do
      InvoiceArchive.create_or_update(%{
        year: archive.year,
        month: archive.month,
        status: "failed",
        error_message: "Reset: generation was interrupted"
      })
    end

    {:noreply, assign(socket, :archives, InvoiceArchive.list_all())}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  def handle_info({:job_update, job_state}, socket) do
    socket = assign(socket, :job, if(job_state.status == :idle, do: nil, else: job_state))

    socket =
      if job_state.status in [:done, :failed, :cancelled] do
        assign(socket, :archives, InvoiceArchive.list_all())
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp progress_percent(nil), do: 0

  defp progress_percent(job) do
    case job.phase do
      :fetching_invoices ->
        0

      :creating_zip ->
        95

      :uploading_s3 ->
        98

      :done ->
        100

      :downloading_pdfs ->
        if job.total > 0, do: round((job.done + job.failed) / job.total * 95), else: 0

      _ ->
        0
    end
  end

  defp progress_text(nil), do: ""

  defp progress_text(job) do
    case job.phase do
      :fetching_invoices ->
        "Fetching invoice list from Stripe..."

      :downloading_pdfs ->
        "Downloading invoices: #{job.done + job.failed}/#{job.total} (#{progress_percent(job)}%)"

      :creating_zip ->
        "Creating ZIP archive..."

      :uploading_s3 ->
        "Uploading to S3..."

      :done ->
        "Complete!"

      _ ->
        "Working..."
    end
  end

  defp month_name(month) do
    Enum.at(
      ~w(January February March April May June July August September October November December),
      month - 1
    )
  end

  defp format_amount(nil), do: "$0.00"

  defp format_amount(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining = rem(abs(cents), 100)
    "$#{dollars}.#{String.pad_leading(to_string(remaining), 2, "0")}"
  end

  defp format_file_size(nil), do: "-"
  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class("generating"), do: "badge-warning"
  defp status_badge_class("pending"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-ghost"

  defp job_running?(job), do: job != nil and job.status == :running

  defp stale_generating?(archive, job) do
    archive.status == "generating" and not job_running?(job)
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-6xl mx-auto">
      <h1 class="text-3xl font-bold mb-2">Invoice Archives</h1>
      <p class="text-sm text-base-content/60 mb-6">
        Generate, download, and manage monthly invoice archive ZIPs from Stripe.
      </p>

      <%!-- ── Generate controls ─────────────────────────────────────── --%>
      <div class="card bg-base-100 border border-base-300 p-4 mb-6">
        <form phx-change="select_period" phx-submit="generate" class="flex items-end gap-4">
          <fieldset class="fieldset">
            <legend class="fieldset-legend">Year</legend>
            <select name="year" class="select select-sm w-28">
              <option :for={y <- @years} value={y} selected={y == @selected_year}>{y}</option>
            </select>
          </fieldset>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">Month</legend>
            <select name="month" class="select select-sm w-36">
              <option :for={m <- 1..12} value={m} selected={m == @selected_month}>
                {month_name(m)}
              </option>
            </select>
          </fieldset>

          <button type="submit" disabled={job_running?(@job)} class="btn btn-sm btn-primary">
            Generate
          </button>
        </form>
      </div>

      <%!-- ── Progress bar ──────────────────────────────────────────── --%>
      <div :if={job_running?(@job)} class="card bg-base-100 border border-base-300 p-4 mb-6">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium">{progress_text(@job)}</span>
          <button phx-click="cancel" class="btn btn-xs btn-soft btn-error">
            Cancel
          </button>
        </div>

        <progress class="progress progress-primary w-full" value={progress_percent(@job)} max="100">
        </progress>

        <div :if={@job.failed > 0} class="mt-2 text-sm text-error">
          {length(@job.errors)} error(s) during download
        </div>
      </div>

      <%!-- ── Job done/failed/cancelled banner ──────────────────────── --%>
      <div :if={@job && @job.status == :done} role="alert" class="alert alert-success mb-6">
        <span>Generation complete! {month_name(@job.month)} {@job.year} archive is ready.</span>
      </div>

      <div :if={@job && @job.status == :failed} role="alert" class="alert alert-error mb-6">
        <span>Generation failed. {Enum.join(@job.errors, "; ")}</span>
      </div>

      <div :if={@job && @job.status == :cancelled} role="alert" class="alert alert-warning mb-6">
        <span>Generation cancelled.</span>
      </div>

      <%!-- ── Confirmation modal ────────────────────────────────────── --%>
      <div :if={@confirm_action} class="modal modal-open">
        <div class="modal-box max-w-sm">
          <h3 class="text-lg font-medium mb-2">
            {if @confirm_action == :delete, do: "Delete Archive", else: "Regenerate Archive"}
          </h3>
          <p class="text-sm text-base-content/70 mb-4">
            {if @confirm_action == :delete,
              do: "This will permanently delete the archive and its S3 file. Continue?",
              else: "This will delete the existing archive and generate a new one. Continue?"}
          </p>
          <div class="modal-action">
            <button phx-click="cancel_confirm" class="btn btn-sm btn-soft">
              Cancel
            </button>
            <button
              phx-click={if @confirm_action == :delete, do: "delete", else: "regenerate"}
              class={[
                "btn btn-sm",
                if(@confirm_action == :delete, do: "btn-error", else: "btn-primary")
              ]}
            >
              {if @confirm_action == :delete, do: "Delete", else: "Regenerate"}
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="cancel_confirm"></div>
      </div>

      <%!-- ── Archives table ────────────────────────────────────────── --%>
      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Month</th>
              <th>Status</th>
              <th>Invoices</th>
              <th>Total Amount</th>
              <th>File Size</th>
              <th>Generated At</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@archives == []}>
              <td colspan="7" class="text-center text-base-content/60 py-6">
                No archives generated yet. Select a month and click Generate to create one.
              </td>
            </tr>
            <tr :for={archive <- @archives}>
              <td class="font-medium">{month_name(archive.month)} {archive.year}</td>
              <td>
                <span class={["badge badge-sm", status_badge_class(archive.status)]}>
                  {archive.status}
                </span>
                <span
                  :if={archive.status == "failed" && archive.error_message}
                  class="block text-xs text-error mt-1 max-w-xs truncate"
                  title={archive.error_message}
                >
                  {archive.error_message}
                </span>
              </td>
              <td class="text-base-content/70">{archive.invoice_count}</td>
              <td class="text-base-content/70">{format_amount(archive.total_amount)}</td>
              <td class="text-base-content/70">{format_file_size(archive.file_size)}</td>
              <td class="text-base-content/70">{format_datetime(archive.updated_at)}</td>
              <td>
                <div class="flex items-center gap-2">
                  <button
                    :if={archive.status == "completed" && archive.s3_key}
                    phx-click="download"
                    phx-value-id={archive.id}
                    class="link link-primary text-sm font-medium"
                  >
                    Download
                  </button>
                  <button
                    :if={archive.status in ["completed", "failed"]}
                    phx-click="confirm_regenerate"
                    phx-value-id={archive.id}
                    disabled={job_running?(@job)}
                    class="link text-warning text-sm font-medium"
                  >
                    Regenerate
                  </button>
                  <button
                    :if={stale_generating?(archive, @job)}
                    phx-click="reset_stale"
                    phx-value-id={archive.id}
                    class="link text-warning text-sm font-medium"
                  >
                    Reset
                  </button>
                  <button
                    :if={archive.status != "generating"}
                    phx-click="confirm_delete"
                    phx-value-id={archive.id}
                    disabled={job_running?(@job)}
                    class="link text-error text-sm font-medium"
                  >
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
