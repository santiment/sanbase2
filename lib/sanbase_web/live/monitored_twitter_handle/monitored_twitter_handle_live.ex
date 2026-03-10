defmodule SanbaseWeb.MonitoredTwitterHandleLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [order_records_by_status: 1]

  alias Sanbase.MonitoredTwitterHandle
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex-1 p:2 sm:p-6 justify-evenly flex flex-col-reverse scrolling-auto">
        <.table id="monitored_twitter_handles" rows={@handles}>
          <:col :let={row} label="Status">
            <AdminSharedComponents.status_badge status={row.status} />
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
              <AdminSharedComponents.approval_button
                name="status"
                value="approved"
                text="Approve"
                disabled={false}
                colors="bg-green-600 hover:bg-green-800"
              />
              <AdminSharedComponents.approval_button
                name="status"
                value="declined"
                text="Decline"
                disabled={false}
                colors="bg-red-600 hover:bg-red-800"
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
  def handle_event(
        "update_status",
        %{"status" => status, "record_id" => record_id} = params,
        socket
      )
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
    |> order_records_by_status()
  end

  defp list_handles() do
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
    |> order_records_by_status()
  end
end
