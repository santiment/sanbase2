defmodule SanbaseWeb.ScheduledDeprecationIndexLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Notifications
  import Sanbase.Utils.DateTime, only: [rough_duration_since: 1]

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
        <h1 class="text-2xl">{@page_title}</h1>
        <.link href={~p"/admin/scheduled_deprecations/new"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" /> Schedule New Deprecation
        </.link>
      </div>

      <div class="rounded-box border border-base-300 overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>API Endpoint</th>
              <th>Deprecation Date</th>
              <th>Contact List</th>
              <th>Overall Status</th>
              <th>Schedule Email</th>
              <th>Reminder Email</th>
              <th>Executed Email</th>
              <th>Created</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={dep <- @deprecations}>
              <td><.code_snippet code={dep.api_endpoint} /></td>
              <td class="text-base-content/70">
                {Timex.format!(dep.deprecation_date, "%Y-%m-%d", :strftime)}
              </td>
              <td class="text-base-content/70">{dep.contact_list_name}</td>
              <td><.status_badge status={dep.status} /></td>
              <td class="text-base-content/70">
                <.email_dispatch_details
                  status={dep.schedule_email_dispatch_status}
                  sent_at={dep.schedule_email_sent_at}
                  scheduled_at={dep.schedule_email_scheduled_at}
                  subject={dep.schedule_email_subject}
                  job_id={dep.schedule_email_job_id}
                />
              </td>
              <td class="text-base-content/70">
                <.email_dispatch_details
                  status={dep.reminder_email_dispatch_status}
                  sent_at={dep.reminder_email_sent_at}
                  scheduled_at={dep.reminder_email_scheduled_at}
                  subject={dep.reminder_email_subject}
                  job_id={dep.reminder_email_job_id}
                />
              </td>
              <td class="text-base-content/70">
                <.email_dispatch_details
                  status={dep.executed_email_dispatch_status}
                  sent_at={dep.executed_email_sent_at}
                  scheduled_at={dep.executed_email_scheduled_at}
                  subject={dep.executed_email_subject}
                  job_id={dep.executed_email_job_id}
                />
              </td>
              <td class="text-base-content/70">{rough_duration_since(dep.inserted_at)} ago</td>
            </tr>
            <tr :if={@deprecations == []}>
              <td colspan="9" class="text-center text-base-content/60 py-6">
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
    status_class =
      case assigns.status do
        "active" -> "badge-info"
        "completed" -> "badge-success"
        "pending" -> "badge-warning"
        "error" -> "badge-error"
        "cancelled" -> "badge-ghost"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <span class={["badge badge-sm", @status_class]}>
      {Phoenix.Naming.humanize(@status)}
    </span>
    """
  end

  defp email_dispatch_details(assigns) do
    status_class =
      case assigns.status do
        "sent" -> "text-success"
        "pending" -> "text-warning"
        "error" -> "text-error"
        _ -> "text-base-content/60"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <div>
      <p class="font-medium">
        {String.slice(@subject, 0, 50) <> if String.length(@subject) > 50, do: "...", else: ""}
      </p>
      <p><span class={["font-semibold", @status_class]}>{Phoenix.Naming.humanize(@status)}</span></p>
      <p :if={@sent_at} class="text-xs text-base-content/60">{format_datetime(@sent_at)}</p>
      <p :if={@status == "pending" and @scheduled_at} class="text-xs text-info">
        Scheduled for: {format_datetime(@scheduled_at)}
      </p>
      <p :if={@job_id} class="text-xs mt-1">
        <.link
          href={"/admin/generic/#{@job_id}?resource=oban_jobs"}
          class="link link-primary"
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
    <code class="kbd kbd-sm">{@code}</code>
    """
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S")
  end
end
