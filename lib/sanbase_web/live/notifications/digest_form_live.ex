defmodule SanbaseWeb.NotificationsLive.DigestFormLive do
  use SanbaseWeb, :live_view
  alias Sanbase.Notifications.EmailNotifier

  def mount(%{"action" => action}, _session, socket) do
    {:ok,
     assign(socket,
       action: action,
       form: to_form(%{})
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center justify-between mb-4">
        <.link
          navigate={~p"/admin2/generic?resource=notifications"}
          class="text-sm text-gray-600 hover:text-gray-900"
        >
          ← Back to Notifications
        </.link>
        <h2 class="text-xl font-bold">
          {format_title(@action)} Email Digest
        </h2>
      </div>

      <div class="bg-white shadow rounded-lg p-6">
        <p class="mb-4 text-gray-600">
          This will send an email digest for all unprocessed {format_title(@action)} notifications from the last 24 hours.
        </p>

        <.form for={@form} phx-submit="send_digest">
          <div>
            <.button type="submit" phx-disable-with="Sending...">
              Send Digest
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  def handle_event("send_digest", _params, socket) do
    EmailNotifier.send_daily_digest(socket.assigns.action)

    {:noreply,
     socket
     |> put_flash(:info, "Email digest triggered successfully!")}
  end

  defp format_title(action) do
    action
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
