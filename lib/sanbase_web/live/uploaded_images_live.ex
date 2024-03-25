defmodule SanbaseWeb.UploadedImagesLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:rows, Sanbase.FileStore.Image.all())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex-1 p:2 sm:p-6 justify-evenly">
        <.table id="uploaded_images" rows={@rows}>
          <:col :let={row} label="Name"><%= row.name %></:col>
          <:col :let={row} label="URL">
            <.link class="underline text-blue-600" href={row.url} target="_blank">
              <%= row.url %>
            </.link>
          </:col>
          <:col :let={row} label="Notes"><%= row.notes %></:col>
          <:col :let={row} label="Uploaded at"><%= row.inserted_at %></:col>
        </.table>
      </div>
    </div>
    """
  end
end
