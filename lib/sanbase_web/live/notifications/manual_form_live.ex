defmodule SanbaseWeb.NotificationsLive.ManualFormLive do
  use SanbaseWeb, :live_view
  alias Sanbase.Notifications.Handler

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(%{"discord_text" => "", "email_text" => "", "email_subject" => ""})
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <.form for={@form} phx-submit="send_notification">
        <div class="space-y-4">
          <div>
            <.input
              field={@form[:discord_text]}
              type="textarea"
              label="Discord Message"
              placeholder="Enter message for Discord..."
            />
          </div>

          <div>
            <.input
              field={@form[:email_subject]}
              type="text"
              label="Email Subject"
              placeholder="Enter email subject..."
            />
          </div>

          <div>
            <.input
              field={@form[:email_text]}
              type="textarea"
              label="Email Message"
              placeholder="Enter message for email..."
            />
          </div>

          <div>
            <.button type="submit" phx-disable-with="Sending...">
              Send Notification
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event(
        "send_notification",
        %{
          "discord_text" => discord_text,
          "email_text" => email_text,
          "email_subject" => email_subject
        },
        socket
      ) do
    params = %{
      discord_text: discord_text,
      email_text: email_text,
      email_subject: email_subject
    }

    case Handler.handle_notification(%{action: "manual", params: params}) do
      {:ok, _notification} ->
        {:noreply,
         socket
         |> put_flash(:info, "Notification sent successfully!")
         |> assign(
           form: to_form(%{"discord_text" => "", "email_text" => "", "email_subject" => ""})
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send notification")}
    end
  end
end
