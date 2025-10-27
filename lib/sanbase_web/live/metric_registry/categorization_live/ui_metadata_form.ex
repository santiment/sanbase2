defmodule SanbaseWeb.CategorizationLive.UIMetadataForm do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.UIMetadata
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"mapping_id" => mapping_id}, _session, socket) do
    {:ok,
     socket
     |> assign(mapping_id: mapping_id)
     |> assign(page_title: "UI Metadata")
     |> assign(prefilled_metric: nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    mode = if Map.has_key?(params, "id"), do: "edit", else: "new"

    {:noreply,
     socket
     |> assign(mode: mode)
     |> setup_form(params, mode)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full max-w-2xl mx-auto">
      <div class="text-gray-800 text-2xl mb-4">
        {@page_title}
      </div>

      <.navigation mapping_id={@mapping_id} metric_info={@metric_info} ui_metadata={@ui_metadata} />

      <div :if={@metric_info} class="mb-6 p-4 bg-gray-50 rounded-lg">
        <div class="text-sm font-medium text-gray-700 mb-1">Metric</div>
        <div class="text-lg font-bold text-gray-900">{@metric_info.metric}</div>
        <div :if={@metric_info.human_readable_name} class="text-sm text-gray-600">
          {@metric_info.human_readable_name}
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
            :if={@metric_select_field == :hidden}
            type="hidden"
            field={@form[:metric]}
            value={@metric_info.metric}
          />

          <span :if={@metric_select_field == :select}>
            <.input
              :if={@metric_select_field == :select}
              type="select"
              label="Metric"
              field={@form[:metric]}
              options={list_metric_variants(@mapping)}
              value={@prefilled_metric || @metric_info.metric}
            />
          </span>

          <.input
            type="text"
            label="UI Human Readable Name"
            field={@form[:ui_human_readable_name]}
            placeholder={@metric_info.human_readable_name}
          />
          <div class="text-xs -mt-4 text-gray-500">
            If empty, the metric's human readable name will be used, if it exists.
          </div>

          <.input
            type="text"
            field={@form[:ui_key]}
            label="UI Key"
            placeholder={@prefilled_metric || @metric_info.metric}
          />

          <.input
            type="select"
            field={@form[:chart_style]}
            label="Chart Style"
            options={[
              {"Not specified", nil},
              {"Line", "line"},
              {"Bar", "bar"},
              {"Area", "area"},
              {"Scatter", "scatter"}
            ]}
            value={nil}
          />

          <.input type="text" field={@form[:unit]} label="Unit" placeholder="e.g., USD, %" />

          <.input
            type="textarea"
            field={@form[:args]}
            value={format_maybe_json_value(@form[:args])}
            label="Additional Arguments (JSON)"
            placeholder="{}"
            phx-debounce="200"
          />

          <.input type="checkbox" field={@form[:show_on_sanbase]} label="Show on Sanbase" />

          <div class="flex justify-between items-center mt-6">
            <div class="flex space-x-2">
              <.link
                navigate={~p"/admin/metric_registry/categorization/ui_metadata/list/#{@mapping_id}"}
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

            <.button :if={@mode == "new"} type="submit" phx-disable-with="Saving...">
              Save UI Metadata
            </.button>
            <.button :if={@mode == "edit"} type="submit" phx-disable-with="Updating...">
              Update UI Metadata
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
        href={~p"/admin/metric_registry/categorization/ui_metadata/list/#{@mapping_id}"}
        icon="hero-list-bullet"
      />
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"ui_metadata" => params}, socket) do
    params = convert_json_args(params)

    changeset =
      socket.assigns.ui_metadata
      |> UIMetadata.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"ui_metadata" => params}, socket) do
    case socket.assigns.mode do
      "new" -> save_ui_metadata(params, socket)
      "edit" -> update_ui_metadata(params, socket)
    end
  end

  def handle_event("delete", _params, socket) do
    mapping_id = socket.assigns.mapping_id

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

  # Form setup functions

  defp save_ui_metadata(params, socket) do
    mapping_id = socket.assigns.mapping_id
    params = convert_json_args(params)

    params =
      Map.merge(params, %{
        "display_order_in_mapping" => socket.assigns.next_display_order,
        "metric_category_mapping_id" => socket.assigns.mapping_id
      })

    case Category.create_ui_metadata(params) do
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
         |> assign(form: to_form(changeset, action: :insert))
         |> put_flash(
           :error,
           "Failed to save UI metadata. Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}"
         )}
    end
  end

  defp update_ui_metadata(params, socket) do
    mapping_id = socket.assigns.mapping_id
    params = convert_json_args(params)

    case Category.update_ui_metadata(socket.assigns.ui_metadata, params) do
      {:ok, _ui_metadata} ->
        {:noreply,
         socket
         |> put_flash(:info, "UI metadata updated successfully")
         |> push_navigate(
           to: ~p"/admin/metric_registry/categorization/ui_metadata/list/#{mapping_id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, action: :insert))
         |> put_flash(
           :error,
           "Failed to save UI metadata. Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}"
         )}
    end
  end

  defp setup_form(socket, %{"id" => ui_metadata_id_str} = _params, "edit") do
    ui_metadata_id = String.to_integer(ui_metadata_id_str)

    if ui_metadata = Category.get_ui_metadata(ui_metadata_id) do
      metric_info = build_metric_info(ui_metadata.metric_category_mapping)
      changeset = UIMetadata.changeset(ui_metadata, %{})

      socket
      |> assign(ui_metadata: ui_metadata)
      |> assign(form: to_form(changeset))
      |> assign(metric_info: metric_info)
      |> assign(page_title: "Edit UI Metadata")
      |> assign(prefilled_metric: nil)
      |> assign(metric_select_field: :none)
    else
      socket
      |> put_flash(:error, "UI metadata not found")
      |> push_navigate(to: ~p"/admin/metric_registry/categorization")
    end
  end

  defp setup_form(socket, %{"mapping_id" => mapping_id_str} = params, "new") do
    mapping_id = String.to_integer(mapping_id_str)

    case Category.get_mapping(mapping_id) do
      {:ok, mapping} ->
        next_display_order = calculate_next_display_order(mapping_id)
        prefilled_metric = Map.get(params, "metric")

        metric_select_field =
          case mapping do
            %{metric_registry: %{parameters: parameters}}
            when is_list(parameters) and parameters != [] ->
              :select

            _ ->
              :hidden
          end

        ui_metadata = %UIMetadata{}
        changeset = UIMetadata.changeset(ui_metadata, %{})

        socket
        |> assign(mapping: mapping)
        |> assign(ui_metadata: ui_metadata)
        |> assign(form: to_form(changeset))
        |> assign(metric_info: build_metric_info(mapping, prefilled_metric))
        |> assign(page_title: "New UI Metadata")
        |> assign(next_display_order: next_display_order)
        |> assign(prefilled_metric: prefilled_metric)
        |> assign(metric_select_field: metric_select_field)

      _ ->
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

  # Helper functions

  defp calculate_next_display_order(mapping_id) do
    ui_metadata_list = Category.list_ui_metadata_by_mapping_id(mapping_id)

    if ui_metadata_list == [] do
      1
    else
      max_order =
        ui_metadata_list
        |> Enum.map(& &1.display_order_in_mapping)
        |> Enum.max(fn -> 0 end)

      max_order + 1
    end
  end

  defp convert_json_args(%{"args" => args_string} = params) when is_binary(args_string) do
    args =
      cond do
        "" == args_string ->
          %{}

        is_binary(args_string) ->
          case Jason.decode(args_string) do
            {:ok, json_map} -> json_map
            {:error, _} -> args_string
          end

        true ->
          args_string
      end

    Map.put(params, "args", args)
  end

  defp build_metric_info(mapping, prefilled_metric \\ nil)

  defp build_metric_info(
         %{metric_registry_id: id, metric_registry: registry} = mapping,
         prefilled_metric
       )
       when not is_nil(id) and not is_nil(registry) do
    human_readable =
      if prefilled_metric do
        {:ok, human_readble} = Sanbase.Metric.human_readable_name(prefilled_metric)
        human_readble
      else
        registry.human_readable_name
      end

    %{
      metric: registry.metric,
      human_readable_name: human_readable,
      source_display: "Registry",
      source_type: "registry",
      category_name: mapping.category && mapping.category.name,
      group_name: mapping.group && mapping.group.name
    }
  end

  defp build_metric_info(%{module: module, metric: metric} = mapping, prefilled_metric)
       when not is_nil(module) and not is_nil(metric) do
    human_readable =
      case Sanbase.Metric.human_readable_name(prefilled_metric || metric) do
        {:ok, human_readable} -> human_readable
        _ -> nil
      end

    %{
      metric: metric,
      human_readable_name: human_readable,
      source_display: "CodeModule",
      source_type: "code",
      category_name: mapping.category && mapping.category.name,
      group_name: mapping.group && mapping.group.name
    }
  end

  defp build_metric_info(_mapping, _prefilled_metric), do: nil

  defp format_maybe_json_value(%{value: nil}), do: "{}"

  defp format_maybe_json_value(%{value: value}) do
    case value do
      %{} = map -> Jason.encode!(map)
      _ -> value
    end
  end

  defp list_metric_variants(mapping) do
    case mapping do
      %{metric_registry: %{} = registry} ->
        Sanbase.Metric.Registry.resolve([registry])
        |> Enum.map(& &1.metric)
        |> Enum.map(fn m -> {m, m} end)

      _ ->
        []
    end
  end
end
