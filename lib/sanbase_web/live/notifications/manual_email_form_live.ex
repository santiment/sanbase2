defmodule SanbaseWeb.NotificationsLive.ManualEmailFormLive do
  use SanbaseWeb, :live_view
  alias Sanbase.Notifications.Handler

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form:
         to_form(%{
           "action" => "message",
           "subject" => "",
           "content" => ""
         })
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
        <h2 class="text-xl font-bold">Email Notification</h2>
      </div>

      <.form for={@form} phx-submit="send_email">
        <div class="space-y-4">
          <div>
            <.input
              type="select"
              field={@form[:action]}
              label="Action"
              options={[{"Message", "message"}, {"Alert", "alert"}]}
            />
          </div>

          <div>
            <.input
              field={@form[:subject]}
              type="text"
              label="Subject"
              placeholder="Enter email subject..."
            />
          </div>

          <div>
            <.input
              field={@form[:content]}
              type="textarea"
              label="Content"
              placeholder="Enter message for email..."
            />
          </div>

          <div>
            <.button type="submit" phx-disable-with="Sending...">
              Send Email
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event(
        "send_email",
        %{"action" => action, "subject" => subject, "content" => content},
        socket
      ) do
    case Handler.handle_manual_notification(%{
           action: action,
           channel: "email",
           params: %{
             subject: subject,
             content: content
           }
         }) do
      {:ok, _notification} ->
        {:noreply,
         socket
         |> put_flash(:info, "Email notification sent successfully!")
         |> assign(form: to_form(%{"action" => "message", "subject" => "", "content" => ""}))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send email notification")}
    end
  end
end
