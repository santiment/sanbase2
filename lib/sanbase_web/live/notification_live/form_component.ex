defmodule SanbaseWeb.NotificationLive.FormComponent do
  use SanbaseWeb, :live_component

  alias Sanbase.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage notification records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="notification-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:step]} type="text" label="Step" />
        <.input field={@form[:status]} type="text" label="Status" />
        <.input field={@form[:scheduled_at]} type="datetime-local" label="Scheduled at" />
        <.input field={@form[:sent_at]} type="datetime-local" label="Sent at" />
        <.input
          field={@form[:channels]}
          type="select"
          multiple
          label="Channels"
          options={[{"Option 1", "option1"}, {"Option 2", "option2"}]}
        />
        <.input field={@form[:content]} type="text" label="Content" />
        <.input field={@form[:display_in_ui]} type="checkbox" label="Display in ui" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Notification</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{notification: notification} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Notifications.change_notification(notification))
     end)}
  end

  @impl true
  def handle_event("validate", %{"notification" => notification_params}, socket) do
    changeset =
      Notifications.change_notification(socket.assigns.notification, notification_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"notification" => notification_params}, socket) do
    save_notification(socket, socket.assigns.action, notification_params)
  end

  defp save_notification(socket, :edit, notification_params) do
    case Notifications.update_notification(socket.assigns.notification, notification_params) do
      {:ok, notification} ->
        notify_parent({:saved, notification})

        {:noreply,
         socket
         |> put_flash(:info, "Notification updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_notification(socket, :new, notification_params) do
    case Notifications.create_notification(notification_params) do
      {:ok, notification} ->
        notify_parent({:saved, notification})

        {:noreply,
         socket
         |> put_flash(:info, "Notification created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
