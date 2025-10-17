defmodule SanbaseWeb.CategorizationLive.UIMetadataForm do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.UIMetadata
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "UI Metadata")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    mode = Map.get(params, "id", "new")
    {:noreply, setup_form(socket, params, mode)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full max-w-2xl mx-auto">
      <div class="text-gray-800 text-2xl mb-4">
        {@page_title}
      </div>

      <.navigation metric_info={@metric_info} mapping={@mapping} />

      <div :if={@metric_info} class="mb-6 p-4 bg-gray-50 rounded-lg">
        <div class="text-sm font-medium text-gray-700 mb-1">Metric</div>
        <div class="text-lg font-bold text-gray-900">{@metric_info.metric}</div>
        <div :if={@metric_info.human_readable_name} class="text-sm text-gray-600">
          {@metric_info.human_readable_name} (Human Readable Name)
        </div>
        <div class="text-xs text-gray-500 mt-1">
          Source: {@metric_info.source_display}
        </div>
        <div :if={@metric_info.category_name} class="text-xs text-gray-500">
          Category: {@metric_info.category_name}
        </div>
        <div :if={@metric_info.group_name} class="text-xs text-gray-500">
          Group: {@metric_info.group_name}
        </div>
      </div>

      <div class="bg-white p-6 rounded-lg shadow">
        <.simple_form for={@form} id="ui-metadata-form" phx-submit="save" phx-change="validate">
          <.input
            type="text"
            label="UI Human Readable Name"
            field={@form[:ui_human_readable_name]}
            placeholder={"e.g., #{@metric_info.human_readable_name}. If empty, the metric's human readable name will be used."}
          />

          <.input
            type="text"
            field={@form[:ui_key]}
            label="UI Key"
            placeholder="e.g., daily_active_addresses"
          />

          <.input
            type="select"
            field={@form[:chart_style]}
            label="Chart Style"
            options={[
              {"Line", "line"},
              {"Bar", "bar"},
              {"Area", "area"},
              {"Scatter", "scatter"}
            ]}
          />

          <.input type="text" field={@form[:unit]} label="Unit" placeholder="e.g., USD, %" />

          <.input
            type="textarea"
            field={@form[:args]}
            label="Additional Arguments (JSON)"
            placeholder="{}"
            phx-debounce="500"
          />

          <.input type="checkbox" field={@form[:show_on_sanbase]} label="Show on Sanbase" />

          <div class="flex justify-between items-center mt-6">
            <div class="flex space-x-2">
              <.link
                navigate={~p"/admin/metric_registry/categorization/ui_metadata/list/#{@mapping.id}"}
                class="text-gray-600 hover:text-gray-900"
              >
                Cancel
              </.link>

              <button
                :if={@ui_metadata && @ui_metadata.id}
                type="button"
                phx-click="delete"
                class="text-red-600 hover:text-red-900"
                data-confirm="Are you sure you want to delete this UI metadata?"
              >
                Delete
              </button>
            </div>

            <.button type="submit" phx-disable-with="Saving...">
              Save UI Metadata
            </.button>
          </div>
        </.simple_form>
      </div>
    </div>
    """
  end

  def navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Categorization"
        href={~p"/admin/metric_registry/categorization"}
        icon="hero-arrow-left"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Back to UI Metadata List"
        href={~p"/admin/metric_registry/categorization/ui_metadata/list/#{@mapping.id}"}
        icon="hero-list-bullet"
      />
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"ui_metadata" => params}, socket) do
    changeset =
      build_changeset(socket.assigns.ui_metadata, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"ui_metadata" => params}, socket) do
    mapping_id = socket.assigns.mapping.id

    case save_ui_metadata(socket.assigns.ui_metadata, params) do
      {:ok, _ui_metadata} ->
        {:noreply,
         socket
         |> put_flash(:info, "UI metadata saved successfully")
         |> push_navigate(
           to: ~p"/admin/metric_registry/categorization/ui_metadata/list/#{mapping_id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset))
         |> put_flash(
           :error,
           "Failed to save UI metadata. Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}"
         )}
    end
  end

  def handle_event("delete", _params, socket) do
    mapping_id = socket.assigns.mapping.id

    case Category.delete_ui_metadata(socket.assigns.ui_metadata) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "UI metadata deleted successfully")
         |> push_navigate(
           to: ~p"/admin/metric_registry/categorization/ui_metadata/list/#{mapping_id}"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete UI metadata")}
    end
  end

  defp setup_form(socket, %{"id" => ui_metadata_id_str}, "edit") do
    ui_metadata_id = String.to_integer(ui_metadata_id_str)
    ui_metadata = Category.get_ui_metadata(ui_metadata_id)

    if ui_metadata do
      ui_metadata = Sanbase.Repo.preload(ui_metadata, [:metric_category_mapping])
      mapping = ui_metadata.metric_category_mapping
      mapping = Sanbase.Repo.preload(mapping, [:metric_registry, :category, :group])
      metric_info = build_metric_info(mapping)

      changeset = build_changeset(ui_metadata, %{})

      socket
      |> assign(mapping: mapping)
      |> assign(ui_metadata: ui_metadata)
      |> assign(form: to_form(changeset))
      |> assign(metric_info: metric_info)
      |> assign(page_title: "Edit UI Metadata")
    else
      socket
      |> put_flash(:error, "UI metadata not found")
      |> push_navigate(to: ~p"/admin/metric_registry/categorization")
    end
  end

  defp setup_form(socket, %{"mapping_id" => mapping_id_str}, "new") do
    mapping_id = String.to_integer(mapping_id_str)
    mapping = MetricCategoryMapping.get(mapping_id)

    if mapping do
      mapping = Sanbase.Repo.preload(mapping, [:metric_registry, :category, :group])
      metric_info = build_metric_info(mapping)

      ui_metadata_list = Category.list_ui_metadata_by_mapping_id(mapping_id)

      next_display_order =
        if ui_metadata_list == [] do
          1
        else
          max_order =
            ui_metadata_list
            |> Enum.map(& &1.display_order_in_mapping)
            |> Enum.max()

          max_order + 1
        end

      ui_metadata = %UIMetadata{
        metric_category_mapping_id: mapping_id,
        display_order_in_mapping: next_display_order
      }

      changeset = build_changeset(ui_metadata, %{})

      socket
      |> assign(mapping: mapping)
      |> assign(ui_metadata: ui_metadata)
      |> assign(form: to_form(changeset))
      |> assign(metric_info: metric_info)
      |> assign(page_title: "New UI Metadata")
    else
      socket
      |> put_flash(:error, "Mapping not found")
      |> push_navigate(to: ~p"/admin/metric_registry/categorization")
    end
  end

  defp setup_form(socket, _params, _mode) do
    socket
    |> put_flash(:error, "Invalid parameters")
    |> push_navigate(to: ~p"/admin/metric_registry/categorization")
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

  defp build_changeset(ui_metadata, params) do
    params = prepare_params(params)

    types = %{
      ui_human_readable_name: :string,
      ui_key: :string,
      chart_style: :string,
      unit: :string,
      args: :string,
      show_on_sanbase: :boolean,
      display_order_in_mapping: :integer,
      metric_category_mapping_id: :integer
    }

    {ui_metadata, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> validate_and_parse_json_args()
  end

  defp prepare_params(params) do
    params
    |> Map.put("metric_category_mapping_id", params["metric_category_mapping_id"])
  end

  defp validate_and_parse_json_args(changeset) do
    case Ecto.Changeset.get_change(changeset, :args) do
      nil ->
        changeset

      "" ->
        Ecto.Changeset.put_change(changeset, :args, %{})

      args_string when is_binary(args_string) ->
        case Jason.decode(args_string) do
          {:ok, json_map} ->
            Ecto.Changeset.put_change(changeset, :args, json_map)

          {:error, _} ->
            Ecto.Changeset.add_error(changeset, :args, "must be valid JSON")
        end

      args when is_map(args) ->
        changeset
    end
  end

  defp save_ui_metadata(%UIMetadata{id: nil} = ui_metadata, params) do
    params = prepare_params_for_save(params, ui_metadata.metric_category_mapping_id)
    Category.create_ui_metadata(params)
  end

  defp save_ui_metadata(%UIMetadata{} = ui_metadata, params) do
    params = prepare_params_for_save(params, ui_metadata.metric_category_mapping_id)
    Category.update_ui_metadata(ui_metadata, params)
  end

  defp prepare_params_for_save(params, mapping_id) do
    params
    |> Map.put("metric_category_mapping_id", mapping_id)
    |> parse_args_field()
    |> atomize_keys()
  end

  defp atomize_keys(params) do
    known_keys = [
      :ui_human_readable_name,
      :ui_key,
      :chart_style,
      :unit,
      :args,
      :show_on_sanbase,
      :display_order_in_mapping,
      :metric_category_mapping_id
    ]

    params
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      atom_key =
        try do
          String.to_existing_atom(k)
        rescue
          ArgumentError -> nil
        end

      if atom_key && atom_key in known_keys do
        Map.put(acc, atom_key, v)
      else
        acc
      end
    end)
  end

  defp parse_args_field(params) do
    case params["args"] do
      nil ->
        Map.put(params, "args", %{})

      "" ->
        Map.put(params, "args", %{})

      args_string when is_binary(args_string) ->
        case Jason.decode(args_string) do
          {:ok, json_map} -> Map.put(params, "args", json_map)
          {:error, _} -> params
        end

      args when is_map(args) ->
        params
    end
  end

  defp format_module_name(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
  end
end
