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

  defp status_badge_class("completed"), do: "bg-green-100 text-green-800"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-800"
  defp status_badge_class("generating"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("pending"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

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
      <h1 class="text-3xl font-bold text-gray-900 mb-2">Invoice Archives</h1>
      <p class="text-sm text-gray-500 mb-6">
        Generate, download, and manage monthly invoice archive ZIPs from Stripe.
      </p>

      <%!-- ── Generate controls ─────────────────────────────────────── --%>
      <div class="bg-white border border-gray-200 rounded-lg p-4 mb-6">
        <form phx-change="select_period" phx-submit="generate" class="flex items-end gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Year</label>
            <select
              name="year"
              class="block w-28 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
            >
              <option :for={y <- @years} value={y} selected={y == @selected_year}>{y}</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Month</label>
            <select
              name="month"
              class="block w-36 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
            >
              <option :for={m <- 1..12} value={m} selected={m == @selected_month}>
                {month_name(m)}
              </option>
            </select>
          </div>

          <button
            type="submit"
            disabled={job_running?(@job)}
            class={"px-4 py-2 rounded-md text-sm font-medium text-white #{if job_running?(@job), do: "bg-indigo-300 cursor-not-allowed", else: "bg-indigo-600 hover:bg-indigo-700"}"}
          >
            Generate
          </button>
        </form>
      </div>

      <%!-- ── Progress bar ──────────────────────────────────────────── --%>
      <div :if={job_running?(@job)} class="bg-white border border-gray-200 rounded-lg p-4 mb-6">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium text-gray-700">
            {progress_text(@job)}
          </span>
          <button phx-click="cancel" class="text-sm text-red-600 hover:text-red-800 font-medium">
            Cancel
          </button>
        </div>

        <div class="w-full bg-gray-200 rounded-full h-3">
          <div
            class="bg-indigo-600 h-3 rounded-full transition-all duration-300"
            style={"width: #{progress_percent(@job)}%"}
          >
          </div>
        </div>

        <div :if={@job.failed > 0} class="mt-2 text-sm text-red-600">
          {length(@job.errors)} error(s) during download
        </div>
      </div>

      <%!-- ── Job done/failed/cancelled banner ──────────────────────── --%>
      <div
        :if={@job && @job.status == :done}
        class="bg-green-50 border border-green-200 rounded-lg p-3 mb-6 text-sm text-green-800"
      >
        Generation complete! {month_name(@job.month)} {@job.year} archive is ready.
      </div>

      <div
        :if={@job && @job.status == :failed}
        class="bg-red-50 border border-red-200 rounded-lg p-3 mb-6 text-sm text-red-800"
      >
        Generation failed. {Enum.join(@job.errors, "; ")}
      </div>

      <div
        :if={@job && @job.status == :cancelled}
        class="bg-yellow-50 border border-yellow-200 rounded-lg p-3 mb-6 text-sm text-yellow-800"
      >
        Generation cancelled.
      </div>

      <%!-- ── Confirmation modal ────────────────────────────────────── --%>
      <div
        :if={@confirm_action}
        class="fixed inset-0 bg-gray-600/50 flex items-center justify-center z-50"
      >
        <div class="bg-white rounded-lg p-6 max-w-sm mx-auto shadow-xl">
          <h3 class="text-lg font-medium text-gray-900 mb-2">
            {if @confirm_action == :delete, do: "Delete Archive", else: "Regenerate Archive"}
          </h3>
          <p class="text-sm text-gray-600 mb-4">
            {if @confirm_action == :delete,
              do: "This will permanently delete the archive and its S3 file. Continue?",
              else: "This will delete the existing archive and generate a new one. Continue?"}
          </p>
          <div class="flex justify-end gap-3">
            <button
              phx-click="cancel_confirm"
              class="px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
            >
              Cancel
            </button>
            <button
              phx-click={if @confirm_action == :delete, do: "delete", else: "regenerate"}
              class={"px-3 py-2 text-sm font-medium text-white rounded-md #{if @confirm_action == :delete, do: "bg-red-600 hover:bg-red-700", else: "bg-indigo-600 hover:bg-indigo-700"}"}
            >
              {if @confirm_action == :delete, do: "Delete", else: "Regenerate"}
            </button>
          </div>
        </div>
      </div>

      <%!-- ── Archives table ────────────────────────────────────────── --%>
      <div class="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Month
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Invoices
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Total Amount
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                File Size
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Generated At
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :if={@archives == []}>
              <td colspan="7" class="px-4 py-8 text-center text-sm text-gray-500">
                No archives generated yet. Select a month and click Generate to create one.
              </td>
            </tr>
            <tr :for={archive <- @archives} class="hover:bg-gray-50">
              <td class="px-4 py-3 text-sm font-medium text-gray-900">
                {month_name(archive.month)} {archive.year}
              </td>
              <td class="px-4 py-3 text-sm">
                <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{status_badge_class(archive.status)}"}>
                  {archive.status}
                </span>
                <span
                  :if={archive.status == "failed" && archive.error_message}
                  class="block text-xs text-red-500 mt-1 max-w-xs truncate"
                  title={archive.error_message}
                >
                  {archive.error_message}
                </span>
              </td>
              <td class="px-4 py-3 text-sm text-gray-600">{archive.invoice_count}</td>
              <td class="px-4 py-3 text-sm text-gray-600">{format_amount(archive.total_amount)}</td>
              <td class="px-4 py-3 text-sm text-gray-600">{format_file_size(archive.file_size)}</td>
              <td class="px-4 py-3 text-sm text-gray-600">{format_datetime(archive.updated_at)}</td>
              <td class="px-4 py-3 text-sm">
                <div class="flex items-center gap-2">
                  <button
                    :if={archive.status == "completed" && archive.s3_key}
                    phx-click="download"
                    phx-value-id={archive.id}
                    class="text-indigo-600 hover:text-indigo-800 font-medium"
                  >
                    Download
                  </button>
                  <button
                    :if={archive.status in ["completed", "failed"]}
                    phx-click="confirm_regenerate"
                    phx-value-id={archive.id}
                    disabled={job_running?(@job)}
                    class={"font-medium #{if job_running?(@job), do: "text-gray-400 cursor-not-allowed", else: "text-yellow-600 hover:text-yellow-800"}"}
                  >
                    Regenerate
                  </button>
                  <button
                    :if={stale_generating?(archive, @job)}
                    phx-click="reset_stale"
                    phx-value-id={archive.id}
                    class="text-orange-600 hover:text-orange-800 font-medium"
                  >
                    Reset
                  </button>
                  <button
                    :if={archive.status != "generating"}
                    phx-click="confirm_delete"
                    phx-value-id={archive.id}
                    disabled={job_running?(@job)}
                    class={"font-medium #{if job_running?(@job), do: "text-gray-400 cursor-not-allowed", else: "text-red-600 hover:text-red-800"}"}
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
