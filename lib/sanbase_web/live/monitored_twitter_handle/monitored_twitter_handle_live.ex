defmodule SanbaseWeb.MonitoredTwitterHandleLive do
  @moduledoc false
  use SanbaseWeb, :live_view

  alias Sanbase.MonitoredTwitterHandle
  alias SanbaseWeb.AdminFormsComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex-1 p:2 sm:p-6 justify-evenly flex flex-col-reverse scrolling-auto">
        <.table id="monitored_twitter_handles" rows={@handles}>
          <:col :let={row} label="Status">
            <AdminFormsComponents.status status={row.status} />
          </:col>
          <:col :let={row} label="Twitter Handle (Clickable link)">
            <.link class="underline text-blue-600" href={"https://x.com/#{row.handle}"}>
              {row.handle}
            </.link>
          </:col>
          <:col :let={row} label="Notes">{row.notes}</:col>
          <:col :let={row} label="User ID">{row.user_id}</:col>
          <:col :let={row} label="Username">{row.user_username}</:col>
          <:col :let={row} label="Email">{row.user_email}</:col>
          <:col :let={row} label="Moderator comment">{row.comment}</:col>
          <:action :let={row}>
            <.form for={@form} phx-submit="update_status">
              <.input type="text" class="" field={@form[:comment]} placeholder="Comment..." />
              <input type="hidden" name="record_id" value={row.id} />
              <AdminFormsComponents.button
                name="status"
                value="approved"
                class="bg-green-600 hover:bg-green-800"
                display_text="Approve"
              />
              <AdminFormsComponents.button
                name="status"
                value="declined"
                class="bg-red-600 hover:bg-red-800"
                display_text="Decline"
              />
            </.form>
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:handles, list_handles())
     |> assign(:form, to_form(%{}))}
  end

  @impl true
  def handle_event("update_status", %{"status" => status, "record_id" => record_id} = params, socket)
      when status in ["approved", "declined"] do
    record_id = String.to_integer(record_id)
    comment = if params["comment"] == "", do: nil, else: params["comment"]
    MonitoredTwitterHandle.update_status(record_id, status, comment)
    handles = update_assigns_handle(socket.assigns.handles, record_id, status, comment)

    {:noreply, assign(socket, :handles, handles)}
  end

  defp update_assigns_handle(handles, record_id, status, comment) do
    handles
    |> Enum.map(fn
      %{id: ^record_id} = record ->
        comment = comment || record.comment

        record
        |> Map.put(:status, status)
        |> Map.put(:comment, comment)

      record ->
        record
    end)
    |> order_records()
  end

  defp list_handles do
    Sanbase.MonitoredTwitterHandle.list_all_submissions()
    |> Enum.map(fn struct ->
      %{
        id: struct.id,
        status: struct.status,
        handle: struct.handle,
        notes: struct.notes,
        comment: struct.comment,
        inserted_at: struct.inserted_at,
        user_id: struct.user.id,
        user_username: struct.user.username,
        user_email: struct.user.email
      }
    end)
    |> order_records()
  end

  defp order_records(handles) do
    Enum.sort_by(
      handles,
      fn record ->
        case record.status do
          "pending_approval" -> 1
          "approved" -> 2
          "declined" -> 3
        end
      end,
      :asc
    )
  end
end
