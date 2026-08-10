defmodule SanbaseWeb.Admin.ApiBusinessOnboardingLive do
  use SanbaseWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Sanbase.Email.ApiBusinessOnboardingList
  alias Sanbase.Email.MailjetApi

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :page_title, "API Business Onboarding List")

    socket =
      if connected?(socket) do
        load_contacts(socket)
      else
        assign(socket, :contacts, AsyncResult.loading())
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_contacts(socket)}
  end

  defp load_contacts(socket) do
    assign_async(socket, :contacts, fn ->
      case MailjetApi.client().fetch_list_emails(ApiBusinessOnboardingList.list_atom()) do
        {:ok, emails} ->
          sorted = Enum.sort(emails)

          {:ok,
           %{
             contacts: %{
               emails: sorted,
               count: length(sorted)
             }
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

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
        bespoke CUSTOM API subscribers. Does not include the new offering (packages,
        Institutional, Enterprise). This reflects Mailjet's live state; new active
        subscribers are added automatically when they purchase.
      </p>

      <.async_result :let={contacts} assign={@contacts}>
        <:loading>
          <div class="text-sm text-base-content/60">Loading contacts from Mailjet...</div>
        </:loading>
        <:failed :let={reason}>
          <div class="alert alert-warning">
            <span>{format_error(reason)}</span>
          </div>
        </:failed>

        <div class="mb-3">
          <span class="text-sm text-base-content/60">
            {contacts.count} contacts
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
              <tr :if={contacts.emails == []}>
                <td colspan="2" class="text-center text-base-content/50 py-4">
                  No contacts on the list.
                </td>
              </tr>
              <tr :for={{email, idx} <- Enum.with_index(contacts.emails, 1)} id={"contact-#{idx}"}>
                <td class="text-base-content/50">{idx}</td>
                <td class="font-mono">{email}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>
    </div>
    """
  end

  defp format_error({:error, :list_not_configured}) do
    "The Mailjet list is not configured for this environment " <>
      "(MAILJET_API_BUSINESS_ONBOARDING_LIST_ID is not set)."
  end

  defp format_error({:error, reason}),
    do: "Failed to load contacts from Mailjet: #{inspect(reason)}"

  defp format_error(other), do: "Failed to load contacts from Mailjet: #{inspect(other)}"
end
