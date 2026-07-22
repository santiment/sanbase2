defmodule SanbaseWeb.Admin.ApiBusinessOnboardingLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Email.ApiBusinessOnboardingList
  alias Sanbase.Email.MailjetApi

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API Business Onboarding List")
     |> load_emails()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_emails(socket)}
  end

  defp load_emails(socket) do
    case MailjetApi.client().fetch_list_emails(ApiBusinessOnboardingList.list_atom()) do
      {:ok, emails} ->
        emails = Enum.sort(emails)

        socket
        |> assign(:emails, emails)
        |> assign(:total_count, length(emails))
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:emails, [])
        |> assign(:total_count, 0)
        |> assign(:error, format_error(reason))
    end
  end

  defp format_error(:list_not_configured) do
    "The Mailjet list is not configured for this environment " <>
      "(MAILJET_API_BUSINESS_ONBOARDING_LIST_ID is not set)."
  end

  defp format_error(reason), do: "Failed to load contacts from Mailjet: #{inspect(reason)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">{@page_title}</h1>
        <button phx-click="refresh" class="btn btn-sm btn-primary">Refresh</button>
      </div>

      <p class="text-sm text-base-content/60 mb-4">
        Contacts currently on the Mailjet onboarding list - Business Pro, Business Max and
        enterprise (CUSTOM) API subscribers. This reflects Mailjet's live state; new active
        subscribers are added automatically when they purchase.
      </p>

      <div :if={@error} class="alert alert-warning mb-4">
        <span>{@error}</span>
      </div>

      <div class="mb-3">
        <span class="text-sm text-base-content/60">
          {if @total_count > 0, do: "#{@total_count} contacts", else: "No contacts"}
        </span>
      </div>

      <div class="rounded-box border border-base-300 overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th class="w-16">#</th>
              <th>Email</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@emails == []}>
              <td colspan="2" class="text-center text-base-content/50 py-4">
                No contacts on the list.
              </td>
            </tr>
            <tr :for={{email, idx} <- Enum.with_index(@emails, 1)} id={"contact-#{idx}"}>
              <td class="text-base-content/50">{idx}</td>
              <td class="font-mono">{email}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
