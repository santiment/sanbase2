defmodule SanbaseWeb.MonitoredTwitterHandleLive.Index do
  use SanbaseWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex-1 p:2 sm:p-6 justify-between flex flex-col-reverse overflow-y-auto scrolling-auto h-96">
        <.table id="monitored_twitter_handles" rows={@handles}>
          <:col :let={row} label="Twitter Handle"><%= row.handle %></:col>
          <:col :let={row} label="Notes"><%= row.notes %></:col>

          <:action :let={row}>
            <.button phx-click={JS.push("decline", value: %{id: row.id})}>
              Decline
            </.button>
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :handles, list_handles())}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    IO.inspect("GOT EVENT")
    {:noreply, socket}
  end

  @impl true
  def handle_event("decline", %{"id" => id}, socket) do
    IO.inspect("GOT EVENT")
    {:noreply, socket}
  end

  def list_handles() do
    Sanbase.MonitoredTwitterHandle.list_all_pending_approval()
    |> Enum.map(fn struct ->
      %{
        id: struct.id,
        handle: struct.handle,
        notes: struct.notes,
        inserted_at: struct.inserted_at
      }
    end)
  end
end
