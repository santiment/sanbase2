defmodule SanbaseWeb.CategorizationLive.MappingForm do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Registry
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Metric Categorization Mapping")
     |> load_data()
     |> setup_form(params)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, setup_form(socket, params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full max-w-2xl mx-auto">
      <div class="text-gray-800 text-2xl mb-4">
        {@page_title}
      </div>

      <.navigation />

      <div class="bg-white p-6 rounded-lg shadow">
        <.simple_form for={@form} id="mapping-form" phx-submit="save" phx-change="validate">
          <div :if={@metric_info} class="mb-6 p-4 bg-gray-50 rounded-lg">
            <div class="text-sm font-medium text-gray-700 mb-1">Metric</div>
            <div class="text-lg font-bold text-gray-900">{@metric_info.metric}</div>
            <div :if={@metric_info.human_readable_name} class="text-sm text-gray-600">
              {@metric_info.human_readable_name}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              Source: {@metric_info.source_display}
            </div>
          </div>

          <.input
            :if={!@metric_info}
            type="select"
            field={@form[:source_type]}
            label="Source Type"
            options={[
              {"Select source type", ""},
              {"Metric Registry", "registry"},
              {"Code Module", "code"}
            ]}
          />

          <.input
            type="select"
            field={@form[:category_id]}
            label="Category"
            options={[
              {"Select a category", ""}
              | Enum.map(@categories, fn c -> {c.name, c.id} end)
            ]}
            required
          />

          <.input
            type="select"
            field={@form[:group_id]}
            label="Group (optional)"
            options={[
              {"No group", ""}
              | Enum.map(@groups_for_category, fn g -> {g.name, g.id} end)
            ]}
          />

          <div class="flex justify-between items-center mt-6">
            <.link
              navigate={~p"/admin/metric_registry/categorization"}
              class="text-gray-600 hover:text-gray-900"
            >
              Cancel
            </.link>

            <.button type="submit" phx-disable-with="Saving...">
              Save Mapping
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
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"metric_category_mapping" => params}, socket) do
    changeset =
      build_changeset(socket.assigns.mapping, params)
      |> Map.put(:action, :validate)

    category_id = params["category_id"]
    groups_for_category = load_groups_for_category(category_id, socket.assigns.categories)

    {:noreply,
     socket
     |> assign(form: to_form(changeset))
     |> assign(groups_for_category: groups_for_category)}
  end

  def handle_event("save", %{"metric_category_mapping" => params}, socket) do
    case save_mapping(socket.assigns.mapping, params, socket.assigns) do
      {:ok, _mapping} ->
        {:noreply,
         socket
         |> put_flash(:info, "Mapping saved successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/categorization")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset))
         |> put_flash(
           :error,
           "Failed to save mapping. Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}"
         )}
    end
  end

  defp load_data(socket) do
    categories = Category.list_categories()

    socket
    |> assign(categories: categories)
    |> assign(groups_for_category: [])
  end

  defp setup_form(socket, %{"id" => id} = _params) do
    mapping = MetricCategoryMapping.get(String.to_integer(id))
    mapping = Sanbase.Repo.preload(mapping, [:metric_registry, :category, :group])

    metric_info = build_metric_info(mapping)
    changeset = build_changeset(mapping, %{})

    groups_for_category =
      load_groups_for_category(mapping.category_id, socket.assigns.categories)

    socket
    |> assign(mapping: mapping)
    |> assign(form: to_form(changeset))
    |> assign(metric_info: metric_info)
    |> assign(groups_for_category: groups_for_category)
    |> assign(page_title: "Edit Metric Categorization")
  end

  defp setup_form(socket, params) do
    mapping = %MetricCategoryMapping{}
    metric_info = extract_metric_info(params)
    initial_params = extract_initial_params(params)
    changeset = build_changeset(mapping, initial_params)

    socket
    |> assign(mapping: mapping)
    |> assign(form: to_form(changeset))
    |> assign(metric_info: metric_info)
    |> assign(page_title: "New Metric Categorization")
  end

  defp extract_metric_info(params) do
    cond do
      Map.has_key?(params, "metric_registry_id") ->
        build_registry_metric_info(params["metric_registry_id"])

      Map.has_key?(params, "module") && Map.has_key?(params, "metric") ->
        build_code_metric_info(params["module"], params["metric"])

      true ->
        nil
    end
  end

  defp build_registry_metric_info(registry_id_str) do
    registry_id = String.to_integer(registry_id_str)
    registry = Sanbase.Repo.get(Registry, registry_id)

    if registry do
      %{
        metric: registry.metric,
        metric_registry_id: registry.id,
        human_readable_name: registry.human_readable_name,
        source_display: "Registry",
        source_type: "registry"
      }
    end
  end

  defp build_code_metric_info(module_name, metric_name) do
    %{
      metric: metric_name,
      human_readable_name: nil,
      source_display: format_module_name(module_name),
      module: module_name,
      source_type: "code"
    }
  end

  defp extract_initial_params(params) do
    cond do
      Map.has_key?(params, "metric_registry_id") ->
        %{
          "metric_registry_id" => params["metric_registry_id"],
          "source_type" => "registry"
        }

      Map.has_key?(params, "module") && Map.has_key?(params, "metric") ->
        %{
          "module" => params["module"],
          "metric" => params["metric"],
          "source_type" => "code"
        }

      true ->
        %{}
    end
  end

  defp build_metric_info(mapping) do
    cond do
      mapping.metric_registry_id && mapping.metric_registry ->
        %{
          metric: mapping.metric_registry.metric,
          human_readable_name: mapping.metric_registry.human_readable_name,
          source_display: "Registry",
          source_type: "registry"
        }

      mapping.module && mapping.metric ->
        %{
          metric: mapping.metric,
          human_readable_name: nil,
          source_display: format_module_name(mapping.module),
          source_type: "code"
        }

      true ->
        nil
    end
  end

  defp build_changeset(mapping, params) do
    types = %{
      metric_registry_id: :integer,
      module: :string,
      metric: :string,
      category_id: :integer,
      group_id: :integer,
      source_type: :string
    }

    {mapping, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:category_id])
  end

  defp save_mapping(%MetricCategoryMapping{id: nil}, params, assigns) do
    attrs = %{
      category_id: parse_integer(params["category_id"]),
      group_id: parse_integer(params["group_id"])
    }

    metric_info = assigns.metric_info

    attrs =
      cond do
        metric_info.source_type == "registry" ->
          Map.put(attrs, :metric_registry_id, assigns.metric_info.metric_registry_id)

        metric_info.source_type == "code" ->
          attrs
          |> Map.put(:module, metric_info.module)
          |> Map.put(:metric, metric_info.metric)

        true ->
          raise(ArgumentError, """
          Invalid params -- the metric info is not properly set
          to determine if the metric is from the metric registry or from a code module

          Contact the backend team to look into the issue.
          Current metric info:
          #{inspect(metric_info)}
          """)
      end

    Category.create_mapping(attrs)
  end

  defp save_mapping(%MetricCategoryMapping{} = mapping, params, _assigns) do
    attrs = %{
      category_id: parse_integer(params["category_id"]),
      group_id: parse_integer(params["group_id"])
    }

    Category.update_mapping(mapping, attrs)
  end

  defp load_groups_for_category(nil, _categories), do: []
  defp load_groups_for_category("", _categories), do: []

  defp load_groups_for_category(category_id, categories) when is_binary(category_id) do
    load_groups_for_category(String.to_integer(category_id), categories)
  end

  defp load_groups_for_category(category_id, _categories) when is_integer(category_id) do
    Category.list_groups_by_category(category_id)
  end

  defp format_module_name(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value) when is_binary(value), do: String.to_integer(value)
end
