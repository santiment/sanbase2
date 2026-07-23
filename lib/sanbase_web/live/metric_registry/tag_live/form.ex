defmodule SanbaseWeb.TagLive.Form do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [format_errors: 1]

  alias Sanbase.Metric.Tag
  alias Sanbase.Metric.Tag.MetricTag
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(
      page_title: "Create New Tag",
      tag: %MetricTag{},
      form: to_form(MetricTag.changeset(%MetricTag{}, %{}), as: :tag),
      action: :new
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         {:ok, tag} <- Tag.get_tag(id) do
      socket
      |> assign(
        page_title: "Edit Tag",
        tag: tag,
        form: to_form(MetricTag.changeset(tag, %{}), as: :tag),
        action: :edit
      )
    else
      _ ->
        socket
        |> put_flash(:error, "Tag not found")
        |> push_navigate(to: ~p"/admin/metric_registry/tags/manage")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-base-content text-2xl mb-4">
        {if @action == :new, do: "Create New Tag", else: "Edit Tag"}
      </div>

      <div class="my-4">
        <AdminSharedComponents.nav_button
          text="Back to Tags"
          href={~p"/admin/metric_registry/tags/manage"}
          icon="hero-arrow-uturn-left"
        />
      </div>

      <.simple_form for={@form} phx-submit="save">
        <.input type="text" field={@form[:name]} label="Tag Name" />
        <.input type="textarea" field={@form[:description]} label="Description" />

        <.button type="submit">Save</.button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"tag" => params}, socket) do
    result =
      case socket.assigns.action do
        :new -> Tag.create_tag(params)
        :edit -> Tag.update_tag(socket.assigns.tag, params)
      end

    case result do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag saved successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/tags/manage")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, format_errors(changeset))
         |> assign(form: to_form(changeset, as: :tag))}
    end
  end
end
