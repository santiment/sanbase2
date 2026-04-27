defmodule SanbaseWeb.CategorizationLive.UIMetadataList do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]
  import SanbaseWeb.Categorization.ReorderComponents

  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Manage UI Metadata",
       mapping: nil,
       metric_info: nil,
       ui_metadata_list: [],
       available_metric_variants: [],
       is_parametrized: false,
       reordering: false,
       editing_id: nil,
       edit_form: nil
     )}
  end

  @impl true
  def handle_params(%{"mapping_id" => mapping_id_str} = _params, _url, socket) do
    mapping_id = parse_int(mapping_id_str, 0)

    if mapping = MetricCategoryMapping.get(mapping_id) do
      ui_metadata_list =
        Category.list_ui_metadata_by_mapping_id(mapping_id)

      metric_info = build_metric_info(mapping)

      resolved_variants = resolve_available_metric_variants(mapping)
      available_variants = filter_available_variants(resolved_variants, ui_metadata_list)
      is_parametrized = has_registry_metric?(mapping) && has_parameters?(mapping)

      {:noreply,
       socket
       |> assign(
         mapping: mapping,
         mapping_id: mapping_id,
         metric_info: metric_info,
         ui_metadata_list: ui_metadata_list,
         available_metric_variants: available_variants,
         is_parametrized: is_parametrized
       )}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Mapping not found")
       |> push_navigate(to: ~p"/admin/metric_registry/categorization")}
    end
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Mapping ID is required")
     |> push_navigate(to: ~p"/admin/metric_registry/categorization")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-2xl mb-4">
        UI Metadata for {@metric_info && @metric_info.metric}
      </div>

      <.navigation mapping_id={@mapping_id} />

      <div :if={@metric_info} class="mb-6 p-4 bg-base-200 rounded-box">
        <div class="text-sm font-medium mb-1">Metric Information</div>
        <div class="text-lg font-bold">{@metric_info.metric}</div>
        <div :if={@metric_info.human_readable_name} class="text-sm text-base-content/60">
          {@metric_info.human_readable_name}
        </div>
        <div class="text-xs text-base-content/50 mt-1">
          Source: {@metric_info.source_display}
        </div>
        <div :if={@metric_info.category_name} class="text-xs text-base-content/50">
          Category: {@metric_info.category_name}
        </div>
        <div :if={@metric_info.group_name} class="text-xs text-base-content/50">
          Group: {@metric_info.group_name}
        </div>
      </div>

      <.ui_metadata_table
        :if={@ui_metadata_list != []}
        mapping_id={@mapping_id}
        ui_metadata_list={@ui_metadata_list}
        editing_id={@editing_id}
      />

      <div
        :if={@ui_metadata_list == []}
        class="card bg-base-100 border border-base-300 p-6 text-center"
      >
        <p class="text-base-content/50 italic mb-2">No UI metadata records yet.</p>
      </div>

      <div :if={@is_parametrized and @available_metric_variants != []}>
        <div class="mt-8 mb-4 text-lg font-semibold">Available Metric Variants</div>
        <.available_variants_table mapping_id={@mapping_id} variants={@available_metric_variants} />
      </div>

      <.modal :if={@reordering} id="reordering-modal" show>
        <.header>Reordering UI Metadata</.header>
        <div class="text-center py-4">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="mt-4">Saving new order...</p>
        </div>
      </.modal>
    </div>
    """
  end

  attr :ui_metadata_list, :list, required: true
  attr :mapping_id, :integer, required: true
  attr :editing_id, :any, default: nil

  def ui_metadata_table(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 overflow-x-auto">
      <table class="table table-zebra table-sm">
        <thead>
          <tr>
            <th>Order</th>
            <th>Metric</th>
            <th>UI Name</th>
            <th>UI Key</th>
            <th>Has Args</th>
            <th>Chart Style</th>
            <th class="text-center">On Sanbase?</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="ui-metadata-list" phx-hook="Sortable">
          <.ui_metadata_row
            :for={{ui_metadata, index} <- Enum.with_index(@ui_metadata_list)}
            mapping_id={@mapping_id}
            ui_metadata={ui_metadata}
            index={index}
            total_count={length(@ui_metadata_list)}
          />
        </tbody>
      </table>
    </div>
    """
  end

  attr :ui_metadata, :map, required: true
  attr :mapping_id, :integer, required: true
  attr :index, :integer, required: true
  attr :total_count, :integer, required: true

  def ui_metadata_row(assigns) do
    ~H"""
    <tr id={"ui-metadata-#{@ui_metadata.id}"} data-id={@ui_metadata.id}>
      <td>
        <.reorder_controls
          index={@index}
          total_count={@total_count}
          item_id={@ui_metadata.id}
          display_order={@ui_metadata.display_order_in_mapping}
        />
      </td>

      <td>{@ui_metadata.metric}</td>
      <td>
        <div :if={@ui_metadata.ui_human_readable_name}>
          {@ui_metadata.ui_human_readable_name}
        </div>
        <div :if={!@ui_metadata.ui_human_readable_name} class="text-base-content/40 italic">
          (not set)
        </div>
      </td>
      <td>
        <div :if={@ui_metadata.ui_key}>
          {@ui_metadata.ui_key}
        </div>
        <div :if={!@ui_metadata.ui_key} class="text-base-content/40 italic">
          (not set)
        </div>
      </td>

      <td>
        <span
          :if={is_map(@ui_metadata.args) and map_size(@ui_metadata.args) > 0}
          class="badge badge-sm badge-success badge-soft"
        >
          YES
        </span>
        <span
          :if={not is_map(@ui_metadata.args) or map_size(@ui_metadata.args) == 0}
          class="badge badge-sm badge-error badge-soft"
        >
          NO
        </span>
      </td>
      <td>{@ui_metadata.chart_style}</td>
      <td class="text-center">
        <span :if={@ui_metadata.show_on_sanbase} class="badge badge-sm badge-success badge-soft">
          YES
        </span>
        <span :if={!@ui_metadata.show_on_sanbase} class="badge badge-sm badge-error badge-soft">
          NO
        </span>
      </td>
      <td>
        <div class="flex space-x-2">
          <.link
            navigate={
              ~p"/admin/metric_registry/categorization/ui_metadata/edit/#{@ui_metadata.id}?mapping_id=#{@mapping_id}"
            }
            class="link link-primary"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            phx-value-id={@ui_metadata.id}
            class="link link-error"
            data-confirm="Are you sure you want to delete this UI metadata?"
          >
            Delete
          </button>
        </div>
      </td>
    </tr>
    """
  end

  attr :mapping_id, :integer, required: true

  def navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AdminSharedComponents.nav_button
        text="Back to Categorization"
        href={~p"/admin/metric_registry/categorization"}
        icon="hero-arrow-left"
      />
      <AdminSharedComponents.nav_button
        icon="hero-plus"
        text="Add UI Metadata"
        href={~p"/admin/metric_registry/categorization/ui_metadata/new?mapping_id=#{@mapping_id}"}
      />
    </div>
    """
  end

  attr :mapping_id, :integer, required: true
  attr :variants, :list, required: true

  def available_variants_table(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 overflow-x-auto">
      <table class="table table-zebra table-sm">
        <thead>
          <tr>
            <th>Metric Name</th>
            <th>Human Readable Name</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={variant <- @variants}>
            <td class="font-medium">{variant.metric}</td>
            <td class="text-base-content/60">{variant.human_readable_name}</td>
            <td>
              <.link
                navigate={
                  ~p"/admin/metric_registry/categorization/ui_metadata/new?mapping_id=#{@mapping_id}&metric=#{variant.metric}"
                }
                class="link link-primary font-medium"
              >
                Add UI Metadata
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl true
  def handle_event("move-up", %{"id" => id}, socket) do
    id = parse_int(id, nil)
    ui_metadata_list = socket.assigns.ui_metadata_list

    index = Enum.find_index(ui_metadata_list, &(&1.id == id))

    if index > 0 do
      current_item = Enum.at(ui_metadata_list, index)
      prev_item = Enum.at(ui_metadata_list, index - 1)

      new_order = [
        %{id: current_item.id, display_order_in_mapping: prev_item.display_order_in_mapping},
        %{id: prev_item.id, display_order_in_mapping: current_item.display_order_in_mapping}
      ]

      case Category.reorder_ui_metadata(new_order) do
        :ok ->
          ui_metadata_list = Category.list_ui_metadata_by_mapping_id(socket.assigns.mapping_id)
          {:noreply, assign(socket, ui_metadata_list: ui_metadata_list)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to reorder")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    id = parse_int(id, nil)
    ui_metadata_list = socket.assigns.ui_metadata_list

    index = Enum.find_index(ui_metadata_list, &(&1.id == id))

    if index < length(ui_metadata_list) - 1 do
      current_item = Enum.at(ui_metadata_list, index)
      next_item = Enum.at(ui_metadata_list, index + 1)

      new_order = [
        %{id: current_item.id, display_order_in_mapping: next_item.display_order_in_mapping},
        %{id: next_item.id, display_order_in_mapping: current_item.display_order_in_mapping}
      ]

      case Category.reorder_ui_metadata(new_order) do
        :ok ->
          ui_metadata_list = Category.list_ui_metadata_by_mapping_id(socket.assigns.mapping_id)
          {:noreply, assign(socket, ui_metadata_list: ui_metadata_list)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to reorder")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    ui_metadata_list = socket.assigns.ui_metadata_list

    if ui_metadata_list != [] do
      new_order =
        ids
        |> parse_reorder_ids("ui-metadata")
        |> Enum.map(fn %{id: id, display_order: order} ->
          %{id: id, display_order_in_mapping: order}
        end)

      socket = assign(socket, reordering: true)

      case Category.reorder_ui_metadata(new_order) do
        :ok ->
          ui_metadata_list = Category.list_ui_metadata_by_mapping_id(socket.assigns.mapping_id)

          {:noreply,
           socket
           |> assign(
             ui_metadata_list: ui_metadata_list,
             reordering: false
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(reordering: false)
           |> put_flash(:error, "Failed to reorder: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id = parse_int(id, nil)

    case Category.get_ui_metadata(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "UI metadata not found")}

      ui_metadata ->
        case Category.delete_ui_metadata(ui_metadata) do
          {:ok, _} ->
            ui_metadata_list =
              Category.list_ui_metadata_by_mapping_id(socket.assigns.mapping_id)

            mapping = socket.assigns.mapping
            resolved_variants = resolve_available_metric_variants(mapping)
            available_variants = filter_available_variants(resolved_variants, ui_metadata_list)

            {:noreply,
             socket
             |> assign(
               ui_metadata_list: ui_metadata_list,
               available_metric_variants: available_variants
             )
             |> put_flash(:info, "UI metadata deleted successfully")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete UI metadata")}
        end
    end
  end

  defp build_metric_info(mapping) do
    cond do
      has_registry_metric?(mapping) -> build_registry_metric_info(mapping)
      has_code_metric?(mapping) -> build_code_metric_info(mapping)
      true -> nil
    end
  end

  defp has_registry_metric?(mapping) do
    mapping.metric_registry_id && mapping.metric_registry
  end

  defp has_code_metric?(mapping) do
    mapping.module && mapping.metric
  end

  defp build_registry_metric_info(mapping) do
    %{
      metric: mapping.metric_registry.metric,
      human_readable_name: mapping.metric_registry.human_readable_name,
      source_display: "Registry",
      source_type: "registry",
      category_name: mapping.category && mapping.category.name,
      group_name: mapping.group && mapping.group.name
    }
  end

  defp build_code_metric_info(mapping) do
    %{
      metric: mapping.metric,
      human_readable_name: nil,
      source_display: format_module_name(mapping.module),
      source_type: "code",
      category_name: mapping.category && mapping.category.name,
      group_name: mapping.group && mapping.group.name
    }
  end

  defp format_module_name(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
  end

  defp resolve_available_metric_variants(mapping) do
    if has_registry_metric?(mapping) && has_parameters?(mapping) do
      case Sanbase.Metric.Registry.by_id(mapping.metric_registry_id) do
        {:ok, registry} ->
          {resolved_metrics, _errors} = Sanbase.Metric.Registry.resolve_safe([registry])
          resolved_metrics

        _ ->
          []
      end
    else
      []
    end
  end

  defp has_parameters?(mapping) do
    mapping.metric_registry &&
      mapping.metric_registry.parameters != []
  end

  defp filter_available_variants(resolved_metrics, existing_ui_metadata) do
    existing_metrics =
      existing_ui_metadata
      |> Enum.filter(& &1.metric)
      |> MapSet.new(& &1.metric)

    Enum.reject(resolved_metrics, fn variant ->
      MapSet.member?(existing_metrics, variant.metric)
    end)
  end
end
