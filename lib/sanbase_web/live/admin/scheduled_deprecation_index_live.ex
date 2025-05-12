defmodule SanbaseWeb.ScheduledDeprecationIndexLive do
  use SanbaseWeb, :live_view
  require Logger

  alias Sanbase.Notifications
  import SanbaseWeb.CoreComponents
  import Sanbase.DateTimeUtils, only: [rough_duration_since: 1]

  @impl true
  def mount(_params, _session, socket) do
    deprecations = Notifications.list_scheduled_deprecations()

    {:ok,
     socket
     |> assign(
       page_title: "Scheduled API Deprecations",
       deprecations: deprecations
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full px-4">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-gray-800 text-2xl">{@page_title}</h1>
        <.link href={~p"/admin/scheduled_deprecations/new"} class="btn btn-primary">
          <.icon name="hero-plus" class="h-5 w-5 mr-1" /> Schedule New Deprecation
        </.link>
      </div>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                API Endpoint
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Deprecation Date
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Contact List
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Overall Status
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Schedule Email
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Reminder Email
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Executed Email
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Created
              </th>
              <th scope="col" class="relative px-6 py-3"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={dep <- @deprecations}>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <.code_snippet code={dep.api_endpoint} />
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {Timex.format!(dep.deprecation_date, "%Y-%m-%d", :strftime)}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {dep.contact_list_name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm">
                <.status_badge status={dep.status} />
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <.email_dispatch_details
                  status={dep.schedule_email_dispatch_status}
                  sent_at={dep.schedule_email_sent_at}
                  scheduled_at={dep.schedule_email_scheduled_at}
                  subject={dep.schedule_email_subject}
                  job_id={dep.schedule_email_job_id}
                />
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <.email_dispatch_details
                  status={dep.reminder_email_dispatch_status}
                  sent_at={dep.reminder_email_sent_at}
                  scheduled_at={dep.reminder_email_scheduled_at}
                  subject={dep.reminder_email_subject}
                  job_id={dep.reminder_email_job_id}
                />
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <.email_dispatch_details
                  status={dep.executed_email_dispatch_status}
                  sent_at={dep.executed_email_sent_at}
                  scheduled_at={dep.executed_email_scheduled_at}
                  subject={dep.executed_email_subject}
                  job_id={dep.executed_email_job_id}
                />
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {rough_duration_since(dep.inserted_at)} ago
              </td>
            </tr>
            <tr :if={@deprecations == []}>
              <td colspan="9" class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 text-center">
                No scheduled deprecations found.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    # Define color classes based on status
    status_class =
      case assigns.status do
        "active" -> "bg-blue-100 text-blue-800"
        "completed" -> "bg-green-100 text-green-800"
        "pending" -> "bg-yellow-100 text-yellow-800"
        "error" -> "bg-red-100 text-red-800"
        "cancelled" -> "bg-gray-100 text-gray-800"
        _ -> "bg-gray-100 text-gray-800"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", @status_class]}>
      {Phoenix.Naming.humanize(@status)}
    </span>
    """
  end

  defp email_dispatch_details(assigns) do
    status_class =
      case assigns.status do
        "sent" -> "text-green-600"
        "pending" -> "text-yellow-600"
        "error" -> "text-red-600"
        _ -> "text-gray-500"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <div>
      <p class="font-medium text-gray-900">
        {String.slice(@subject, 0, 50) <> if String.length(@subject) > 50, do: "...", else: ""}
      </p>
      <p><span class={["font-semibold", @status_class]}>{Phoenix.Naming.humanize(@status)}</span></p>
      <p :if={@sent_at} class="text-xs text-gray-500">{format_datetime(@sent_at)}</p>
      <p :if={@status == "pending" and @scheduled_at} class="text-xs text-blue-500">
        Scheduled for: {format_datetime(@scheduled_at)}
      </p>
      <p :if={@job_id} class="text-xs mt-1">
        <.link
          href={"/admin/generic/#{@job_id}?resource=oban_jobs"}
          class="text-blue-600 hover:underline"
          target="_blank"
        >
          Email Job {@job_id}
        </.link>
      </p>
    </div>
    """
  end

  defp code_snippet(assigns) do
    ~H"""
    <code class="px-2 py-1 text-sm bg-gray-100 rounded">{@code}</code>
    """
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S")
  end
end
