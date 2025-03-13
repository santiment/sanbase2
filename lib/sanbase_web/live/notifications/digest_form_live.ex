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
       current_group_index: 0,
       show_recipients_modal: false
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
        <.email_preview
          :if={@preview_mode}
          action={@action}
          preview_groups={@preview_groups}
          current_group_index={@current_group_index}
          email_recipients={@email_recipients}
          email_content={@email_content}
        />

        <.digest_form :if={!@preview_mode} action={@action} form={@form} />
      </div>

      <.modal
        :if={@show_recipients_modal}
        id="recipients-modal"
        show
        on_cancel={JS.push("hide_recipients_modal")}
      >
        <div class="flex items-center justify-between w-full mb-4">
          <h2 class="text-lg font-semibold">All Recipients ({length(@email_recipients)})</h2>
        </div>

        <div class="mt-4 max-h-[60vh] overflow-y-auto">
          <ul class="list-disc pl-5 space-y-1">
            <li :for={recipient <- @email_recipients} class="text-sm text-gray-700">
              {recipient}
            </li>
          </ul>
        </div>

        <div class="flex justify-end mt-6">
          <.button
            type="button"
            phx-click="hide_recipients_modal"
            class="bg-gray-500 hover:bg-gray-600"
          >
            Close
          </.button>
        </div>
      </.modal>
    </div>
    """
  end

  attr :action, :string, required: true
  attr :preview_groups, :list, required: true
  attr :current_group_index, :integer, required: true
  attr :email_recipients, :list, required: true
  attr :email_content, :string, required: true

  def email_preview(assigns) do
    current_group = Enum.at(assigns.preview_groups, assigns.current_group_index)
    assigns = assign(assigns, :current_group, current_group)

    ~H"""
    <div class="mb-6">
      <h3 class="text-lg font-semibold mb-2">Email Preview</h3>

      <.group_navigation
        :if={length(@preview_groups) > 1}
        preview_groups={@preview_groups}
        current_group_index={@current_group_index}
        current_group={@current_group}
        action={@action}
      />

      <.group_info
        :if={length(@preview_groups) == 1 && @current_group}
        current_group={@current_group}
        action={@action}
      />

      <.recipients_list email_recipients={@email_recipients} />

      <.email_content_preview email_content={@email_content} />

      <div class="flex space-x-3 mt-4">
        <.button type="button" phx-click="send_digest" class="bg-green-600 hover:bg-green-700">
          Confirm & Send
        </.button>
        <.button type="button" phx-click="cancel_preview" class="bg-gray-500 hover:bg-gray-600">
          Cancel
        </.button>
      </div>
    </div>
    """
  end

  attr :preview_groups, :list, required: true
  attr :current_group_index, :integer, required: true
  attr :current_group, :map, required: true
  attr :action, :string, required: true

  def group_navigation(assigns) do
    ~H"""
    <div class="mb-4 flex items-center justify-between">
      <div class="text-sm text-gray-600">
        Showing group {@current_group_index + 1} of {length(@preview_groups)}
        <.group_badges :if={@current_group} current_group={@current_group} action={@action} />
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
    """
  end

  attr :current_group, :map, required: true
  attr :action, :string, required: true

  def group_info(assigns) do
    ~H"""
    <div class="mb-4">
      <.group_badges current_group={@current_group} action={@action} />
    </div>
    """
  end

  attr :current_group, :map, required: true
  attr :action, :string, required: true

  def group_badges(assigns) do
    ~H"""
    <div class="mt-1">
      <span
        :if={@action == "metric_deleted"}
        class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
      >
        Step: {format_step(@current_group.step)}
      </span>
      <span
        :if={@action == "metric_deleted" && @current_group.scheduled_at}
        class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800 ml-2"
      >
        Deprecation Scheduled At: {format_date(@current_group.scheduled_at)}
      </span>
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 ml-2">
        {@current_group.notification_count} notification{if @current_group.notification_count != 1,
          do: "s"}
      </span>
    </div>
    """
  end

  attr :email_recipients, :list, required: true

  def recipients_list(assigns) do
    recipient_count = length(assigns.email_recipients)
    display_recipients = Enum.take(assigns.email_recipients, 10)

    assigns =
      assign(assigns,
        recipient_count: recipient_count,
        display_recipients: display_recipients
      )

    ~H"""
    <div class="mb-4">
      <h4 class="text-md font-medium mb-1">
        Recipients:
        <span class="text-sm font-normal text-gray-600">
          ({@recipient_count} total)
        </span>
      </h4>
      <div class="bg-gray-50 p-3 rounded border max-h-40 overflow-y-auto">
        <p :if={Enum.empty?(@email_recipients)} class="text-gray-500 italic">
          No recipients found
        </p>

        <div :if={!Enum.empty?(@email_recipients)}>
          <ul class="list-disc pl-5">
            <li :for={recipient <- @display_recipients} class="text-sm text-gray-700">
              {recipient}
            </li>
          </ul>

          <div :if={@recipient_count > 0} class="mt-2 text-center">
            <button
              type="button"
              phx-click="show_recipients_modal"
              class="text-sm text-blue-600 hover:text-blue-800 hover:underline"
            >
              Show all {@recipient_count} recipients
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :email_content, :string, required: true

  def email_content_preview(assigns) do
    ~H"""
    <div class="mb-4">
      <h4 class="text-md font-medium mb-1">Email Content:</h4>
      <div class="bg-gray-50 p-3 rounded border">
        <p :if={!@email_content} class="text-gray-500 italic">
          No content to preview
        </p>
        <div
          :if={@email_content}
          class="email-content-preview border rounded p-4 bg-white overflow-auto"
        >
          <iframe srcdoc={@email_content} class="w-full min-h-[400px] border-0"></iframe>
        </div>
      </div>
    </div>
    """
  end

  attr :action, :string, required: true
  attr :form, :any, required: true

  def digest_form(assigns) do
    ~H"""
    <div>
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

  def handle_event("show_recipients_modal", _params, socket) do
    {:noreply, assign(socket, show_recipients_modal: true)}
  end

  def handle_event("hide_recipients_modal", _params, socket) do
    {:noreply, assign(socket, show_recipients_modal: false)}
  end

  def handle_event("cancel_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(
       preview_mode: false,
       email_content: nil,
       email_recipients: [],
       preview_groups: [],
       current_group_index: 0,
       show_recipients_modal: false
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
       current_group_index: 0,
       show_recipients_modal: false
     )
     |> put_flash(:info, "Email digest sending job scheduled successfully!")}
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
    MailjetApi.client().fetch_list_emails(list_id)
  end

  defp metric_updates_list do
    Sanbase.Utils.Config.module_get(Sanbase.Notifications, :mailjet_metric_updates_list)
    |> String.to_atom()
  end
end
