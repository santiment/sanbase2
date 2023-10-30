defmodule SanbaseWeb.MonitoredTwitterHandleLive.Index do
  use SanbaseWeb, :live_view

  IO.inspect("COMPILING LIVE ")

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div
        id="monitored_twitter_handles"
        class="flex-1 p:2 sm:p-6 justify-between flex flex-col-reverse overflow-y-auto scrolling-auto h-96"
      >
        <.table id="monitored_twitter_handles" rows={@streams.messages}>
          <:col :let={{_id, message}} label="Twitter Handle" class="w-8"><%= message.handle %></:col>
          <:col :let={{_id, message}} label="Notes"><%= message.notes %></:col>
          <:col :let={{_id, message}} label="Submitted On"><%= message.inserted_at %></:col>
        </.table>
      </div>

      <form phx-submit="approve">
        <input type="text" name="approve" />
        <.button type="submit">Approve</.button>
      </form>
      <form phx-submit="decline">
        <input type="text" name="decline" />
        <.button type="submit">Decline</.button>
      </form>
    </div>
    """
  end

  @impl true
  def update(%{product: product} = assigns, socket) do
    changeset = Catalog.change_product(product)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset =
      socket.assigns.product
      |> Catalog.change_product(product_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"product" => product_params}, socket) do
    save_product(socket, socket.assigns.action, product_params)
  end

  defp save_product(socket, :edit, product_params) do
    case Catalog.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        notify_parent({:saved, product})

        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_product(socket, :new, product_params) do
    case Catalog.create_product(product_params) do
      {:ok, product} ->
        notify_parent({:saved, product})

        {:noreply,
         socket
         |> put_flash(:info, "Product created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
