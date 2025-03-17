defmodule SanbaseWeb.NotificationsLive.ManualDiscordFormLive do
  use SanbaseWeb, :live_view
  alias Sanbase.Notifications.Handler

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form:
         to_form(%{
           "action" => "message",
           "discord_channel" => "metric_updates",
           "content" => ""
         })
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center justify-between mb-4">
        <.link
          navigate={~p"/admin/generic?resource=notifications"}
          class="text-sm text-gray-600 hover:text-gray-900"
        >
          ← Back to Notifications
        </.link>
        <h2 class="text-xl font-bold">Discord Notification</h2>
      </div>
      <.form for={@form} phx-submit="send_discord">
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
              type="select"
              field={@form[:discord_channel]}
              label="Discord Channel"
              options={[{"Metric Updates", "metric_updates"}]}
            />
          </div>

          <div>
            <.input
              field={@form[:content]}
              type="textarea"
              label="Content"
              placeholder="Enter message for Discord..."
            />
          </div>

          <div>
            <.button type="submit" phx-disable-with="Sending...">
              Send to Discord
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event(
        "send_discord",
        %{"action" => action, "content" => content, "discord_channel" => discord_channel},
        socket
      ) do
    case Handler.handle_manual_notification(%{
           action: action,
           channel: "discord",
           params: %{
             content: content,
             discord_channel: discord_channel
           }
         }) do
      {:ok, _notification} ->
        {:noreply,
         socket
         |> put_flash(:info, "Discord notification sent successfully!")
         |> assign(
           form:
             to_form(%{"action" => "message", "discord_channel" => "general", "content" => ""})
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send Discord notification")}
    end
  end
end
