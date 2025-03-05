defmodule SanbaseWeb.NotificationsLive.DigestFormLive do
  use SanbaseWeb, :live_view
  alias Sanbase.Notifications.EmailNotifier
  alias Sanbase.Notifications.TemplateRenderer
  alias Sanbase.Email.MailjetApi

  def mount(%{"action" => action}, _session, socket) do
    {:ok,
     assign(socket,
       action: action,
       form: to_form(%{}),
       preview_mode: false,
       email_content: nil,
       email_recipients: [],
       preview_groups: [],
       current_group_index: 0
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
        <%= if @preview_mode do %>
          <div class="mb-6">
            <h3 class="text-lg font-semibold mb-2">Email Preview</h3>

            <%= if length(@preview_groups) > 1 do %>
              <div class="mb-4 flex items-center justify-between">
                <div class="text-sm text-gray-600">
                  Showing group {@current_group_index + 1} of {length(@preview_groups)}
                  <%= if current_group = Enum.at(@preview_groups, @current_group_index) do %>
                    <div class="mt-1">
                      <%= if @action == "metric_deleted" do %>
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                          Step: {format_step(current_group.step)}
                        </span>
                        <%= if current_group.scheduled_at do %>
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800 ml-2">
                            Scheduled: {format_date(current_group.scheduled_at)}
                          </span>
                        <% end %>
                      <% end %>
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 ml-2">
                        {current_group.notification_count} notification{if current_group.notification_count !=
                                                                             1,
                                                                           do: "s"}
                      </span>
                    </div>
                  <% end %>
                </div>
                <div class="flex space-x-2">
                  <.button
                    type="button"
                    phx-click="prev_group"
                    disabled={@current_group_index == 0}
                    class="text-sm px-2 py-1"
                  >
                    Previous
                  </.button>
                  <.button
                    type="button"
                    phx-click="next_group"
                    disabled={@current_group_index == length(@preview_groups) - 1}
                    class="text-sm px-2 py-1"
                  >
                    Next
                  </.button>
                </div>
              </div>
            <% else %>
              <%= if current_group = Enum.at(@preview_groups, 0) do %>
                <div class="mb-4">
                  <%= if @action == "metric_deleted" do %>
                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                      Step: {format_step(current_group.step)}
                    </span>
                    <%= if current_group.scheduled_at do %>
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800 ml-2">
                        Scheduled: {format_date(current_group.scheduled_at)}
                      </span>
                    <% end %>
                  <% end %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 ml-2">
                    {current_group.notification_count} notification{if current_group.notification_count !=
                                                                         1,
                                                                       do: "s"}
                  </span>
                </div>
              <% end %>
            <% end %>

            <div class="mb-4">
              <h4 class="text-md font-medium mb-1">Recipients:</h4>
              <div class="bg-gray-50 p-3 rounded border max-h-40 overflow-y-auto">
                <%= if Enum.empty?(@email_recipients) do %>
                  <p class="text-gray-500 italic">No recipients found</p>
                <% else %>
                  <ul class="list-disc pl-5">
                    <%= for recipient <- @email_recipients do %>
                      <li class="text-sm text-gray-700">{recipient}</li>
                    <% end %>
                  </ul>
                <% end %>
              </div>
            </div>

            <div class="mb-4">
              <h4 class="text-md font-medium mb-1">Email Content:</h4>
              <div class="bg-gray-50 p-3 rounded border">
                <%= if @email_content do %>
                  <div class="email-content-preview border rounded p-4 bg-white overflow-auto">
                    <iframe srcdoc={@email_content} class="w-full min-h-[400px] border-0"></iframe>
                  </div>
                <% else %>
                  <p class="text-gray-500 italic">No content to preview</p>
                <% end %>
              </div>
            </div>

            <div class="flex space-x-3 mt-4">
              <.button type="button" phx-click="send_digest" class="bg-green-600 hover:bg-green-700">
                Confirm & Send
              </.button>
              <.button type="button" phx-click="cancel_preview" class="bg-gray-500 hover:bg-gray-600">
                Cancel
              </.button>
            </div>
          </div>
        <% else %>
          <p class="mb-4 text-gray-600">
            This will send an email digest for all unprocessed {format_title(@action)} notifications from the last 24 hours.
          </p>

          <.form for={@form} phx-submit="preview_digest">
            <div>
              <.button type="submit" phx-disable-with="Generating Preview...">
                Preview Digest
              </.button>
            </div>
          </.form>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("preview_digest", _params, socket) do
    action = socket.assigns.action
    notifications = EmailNotifier.get_unprocessed_notifications(action)

    if Enum.empty?(notifications) do
      {:noreply,
       socket
       |> put_flash(:info, "No unprocessed notifications found for preview.")}
    else
      # Generate email content previews for all groups
      notifications_groups = EmailNotifier.group_notifications(notifications, action)
      preview_groups = generate_all_preview_groups(notifications_groups, action)

      # Get the first group's content to display initially
      first_group_content =
        if Enum.any?(preview_groups), do: Enum.at(preview_groups, 0).content, else: nil

      # Get email recipients
      {:ok, email_recipients} = get_email_recipients()

      {:noreply,
       socket
       |> assign(
         preview_mode: true,
         email_content: first_group_content,
         email_recipients: email_recipients,
         preview_groups: preview_groups,
         current_group_index: 0
       )}
    end
  end

  def handle_event("next_group", _params, socket) do
    %{current_group_index: current_index, preview_groups: groups} = socket.assigns

    if current_index < length(groups) - 1 do
      new_index = current_index + 1
      new_content = Enum.at(groups, new_index).content

      {:noreply, assign(socket, current_group_index: new_index, email_content: new_content)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev_group", _params, socket) do
    %{current_group_index: current_index, preview_groups: groups} = socket.assigns

    if current_index > 0 do
      new_index = current_index - 1
      new_content = Enum.at(groups, new_index).content

      {:noreply, assign(socket, current_group_index: new_index, email_content: new_content)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(
       preview_mode: false,
       email_content: nil,
       email_recipients: [],
       preview_groups: [],
       current_group_index: 0
     )}
  end

  def handle_event("send_digest", _params, socket) do
    EmailNotifier.send_daily_digest(socket.assigns.action)

    {:noreply,
     socket
     |> assign(
       preview_mode: false,
       email_content: nil,
       email_recipients: [],
       preview_groups: [],
       current_group_index: 0
     )
     |> put_flash(:info, "Email digest sent successfully!")}
  end

  defp format_title(action) do
    action
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp generate_all_preview_groups(notifications_groups, action) do
    notifications_groups
    |> Enum.map(fn {key, group_notifications} ->
      all_params = EmailNotifier.combine_notification_params(group_notifications)
      step = List.first(group_notifications).step
      notification_count = length(group_notifications)

      # For metric_deleted, extract the scheduled_at date from the key or params
      scheduled_at =
        case action do
          "metric_deleted" ->
            case key do
              {_step, scheduled_date} when not is_nil(scheduled_date) -> scheduled_date
              _ -> all_params["scheduled_at"]
            end

          _ ->
            nil
        end

      # Generate the email content for this group
      content =
        TemplateRenderer.render_content(%{
          action: action,
          params: all_params,
          step: step,
          channel: "email",
          mime_type: "text/html"
        })

      # Create a map with group info and content
      %{
        key: key,
        step: step,
        notification_count: notification_count,
        scheduled_at: scheduled_at,
        content: content
      }
    end)
  end

  defp format_step(step) when is_binary(step) do
    step
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_step(nil), do: "Default"

  defp format_date(date) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, datetime, _} -> format_date(datetime)
      _ -> date
    end
  end

  defp format_date(%DateTime{} = date) do
    Calendar.strftime(date, "%b %d, %Y at %H:%M UTC")
  end

  defp format_date(nil), do: "Not scheduled"

  defp get_email_recipients do
    # Get the configured mailing list
    list_id = metric_updates_list()
    MailjetApi.client().list_subscribed_emails(list_id)
  end

  defp metric_updates_list do
    Sanbase.Utils.Config.module_get(Sanbase.Notifications, :mailjet_metric_updates_list)
    |> String.to_atom()
  end
end
