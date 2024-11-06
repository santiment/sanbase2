defmodule SanbaseWeb.ManualNotificationLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Notifications

  @channel_discord :discord
  @channel_email :email

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create Manual Notification",
       form:
         to_form(
           %{
             "channels_discord" => "true",
             "channels_email" => "false",
             "content" => "",
             "scheduled_at" => ""
           },
           as: "notification"
         ),
       notification: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8">
      <h1 class="text-2xl font-bold mb-6">Create Manual Notification</h1>

      <.form for={@form} phx-submit="save" class="space-y-6">
        <div>
          <.label>Channels</.label>
          <div class="mt-2 space-y-2">
            <.input
              type="checkbox"
              field={@form[:channels_discord]}
              value="true"
              checked
              label="Discord"
              name="notification[channels_discord]"
            />
            <.input
              type="checkbox"
              field={@form[:channels_email]}
              value="true"
              label="Email"
              name="notification[channels_email]"
            />
          </div>
        </div>

        <div>
          <.label>Content</.label>
          <.input type="textarea" field={@form[:content]} rows="4" required class="w-full" />
        </div>

        <div>
          <.label>Schedule For (optional)</.label>
          <.input type="datetime-local" field={@form[:scheduled_at]} class="w-full" />
        </div>

        <.button type="submit" phx-disable-with="Creating...">
          Create Notification
        </.button>
      </.form>

      <%= if @notification do %>
        <div class="mt-6 p-4 bg-green-100 text-green-700 rounded">
          Notification created successfully!
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"notification" => notification_params}, socket) do
    # Convert the checkbox boolean values to actual channel names
    discord_selected? = notification_params["channels_discord"] == "true"
    email_selected? = notification_params["channels_email"] == "true"

    channels =
      []
      |> then(fn list -> if discord_selected?, do: [@channel_discord | list], else: list end)
      |> then(fn list -> if email_selected?, do: [@channel_email | list], else: list end)
      |> then(fn list -> if list == [], do: [@channel_discord], else: list end)

    scheduled_at =
      case notification_params["scheduled_at"] do
        "" -> DateTime.utc_now()
        datetime_str -> parse_datetime(datetime_str)
      end

    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :manual,
        scheduled_at: scheduled_at,
        status: :pending,
        requires_verification: false,
        verified: true
      })

    {:ok, notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :once,
        status: :pending,
        scheduled_at: scheduled_at,
        channels: channels,
        display_in_ui: true,
        content: notification_params["content"]
      })

    {:noreply,
     assign(socket,
       notification: notification,
       form:
         to_form(
           %{
             "channels_discord" => "true",
             "channels_email" => "false",
             "content" => "",
             "scheduled_at" => ""
           },
           as: "notification"
         )
     )}
  end

  defp parse_datetime(datetime_str) do
    [date, time] = String.split(datetime_str, "T")
    [year, month, day] = String.split(date, "-")
    [hour, minute] = String.split(time, ":")

    {:ok, datetime} =
      NaiveDateTime.new(
        String.to_integer(year),
        String.to_integer(month),
        String.to_integer(day),
        String.to_integer(hour),
        String.to_integer(minute),
        0
      )

    DateTime.from_naive!(datetime, "Etc/UTC")
  end
end
