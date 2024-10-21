defmodule SanbaseWeb.NotificationActionLive.FormComponent do
  use SanbaseWeb, :live_component

  alias Sanbase.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage notification_action records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="notification_action-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:action_type]} type="text" label="Action type" />
        <.input field={@form[:scheduled_at]} type="datetime-local" label="Scheduled at" />
        <.input field={@form[:status]} type="text" label="Status" />
        <.input field={@form[:requires_verification]} type="checkbox" label="Requires verification" />
        <.input field={@form[:verified]} type="checkbox" label="Verified" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Notification action</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{notification_action: notification_action} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Notifications.change_notification_action(notification_action))
     end)}
  end

  @impl true
  def handle_event("validate", %{"notification_action" => notification_action_params}, socket) do
    changeset =
      Notifications.change_notification_action(
        socket.assigns.notification_action,
        notification_action_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"notification_action" => notification_action_params}, socket) do
    save_notification_action(socket, socket.assigns.action, notification_action_params)
  end

  defp save_notification_action(socket, :edit, notification_action_params) do
    case Notifications.update_notification_action(
           socket.assigns.notification_action,
           notification_action_params
         ) do
      {:ok, notification_action} ->
        notify_parent({:saved, notification_action})

        {:noreply,
         socket
         |> put_flash(:info, "Notification action updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_notification_action(socket, :new, notification_action_params) do
    case Notifications.create_notification_action(notification_action_params) do
      {:ok, notification_action} ->
        notify_parent({:saved, notification_action})

        {:noreply,
         socket
         |> put_flash(:info, "Notification action created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
