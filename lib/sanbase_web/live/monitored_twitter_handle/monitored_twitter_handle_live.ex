defmodule SanbaseWeb.MonitoredTwitterHandleLive do
  use SanbaseWeb, :live_view

  alias Sanbase.MonitoredTwitterHandle

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex-1 p:2 sm:p-6 justify-between flex flex-col-reverse scrolling-auto">
        <.table id="monitored_twitter_handles" rows={@handles}>
          <:col :let={row} label="Twitter Handle"><%= row.handle %></:col>
          <:col :let={row} label="Status"><%= row.status %></:col>
          <:col :let={row} label="Notes"><%= row.notes %></:col>
          <:col :let={row} label="Moderator comment"><%= row.comment %></:col>
          <:action :let={row}>
            <.form for={@form} phx-submit="update_status">
              <.input type="text" field={@form[:comment]} placeholder="Comment..." />
              <input type="hidden" name="record_id" value={row.id} />
              <.button name="status" value="approved">Approve</.button>
              <.button name="status" value="declined">Decline</.button>
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
    |> order_records()
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
        inserted_at: struct.inserted_at
      }
    end)
    |> order_records()
  end

  defp order_records(handles) do
    handles
    |> Enum.sort_by(
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
