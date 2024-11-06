defmodule SanbaseWeb.MetricRegistryFormLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents

  alias Sanbase.Metric.Registry
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(params, _session, socket) do
    {:ok, metric_registry} =
      case socket.assigns.live_action do
        :new -> {:ok, %Registry{}}
        :edit -> Registry.by_id(Map.fetch!(params, "id"))
      end

    form = metric_registry |> Registry.changeset(%{}) |> to_form()

    {:ok,
     socket
     |> assign(
       metric_registry: metric_registry,
       age_title: page_title(socket.assigns.live_action),
       form: form
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <h1 class="text-gray-800 text-2xl">
        <span :if={@live_action == :edit}>
          Showing details for <span class="text-blue-700"><%= @metric_registry.metric %></span>
        </span>
        <span :if={@live_action == :new} class="text-blue-700">
          Creating a new metric
        </span>
      </h1>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/metric_registry"}
          icon="hero-arrow-uturn-left"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={@live_action == :edit}
          text="See Metric"
          href={~p"/metric_registry/show/#{@metric_registry}"}
          icon="hero-arrow-right-circle"
        />
      </div>
      <.simple_form id="metric_registry_form" for={@form} phx-change="validate" phx-submit="save">
        <.input type="text" id="input-metric" field={@form[:metric]} label="Metric" />
        <.input
          type="text"
          id="input-internal-metric"
          field={@form[:internal_metric]}
          label="Internal Metric"
        />
        <.input
          type="text"
          id="input-human-readable-name"
          field={@form[:human_readable_name]}
          label="Human Readable Name"
        />
        <.aliases_input form={@form} />

        <.tables_input form={@form} />
        <.input type="text" id="input-min-interval" field={@form[:min_interval]} label="Min Interval" />
        <.input
          type="select"
          id="input-aggregation"
          field={@form[:aggregation]}
          label="Default Aggregation"
          options={Registry.aggregations()}
        />

        <.input
          type="select"
          id="input-access"
          field={@form[:access]}
          label="Access"
          options={["free", "restricted"]}
        />
        <.input
          type="select"
          id="input-exposed-environments"
          field={@form[:exposed_environments]}
          label="Exposed on Environments"
          options={["all", "stage", "prod"]}
        />

        <.input
          type="select"
          id="input-data-type"
          field={@form[:data_type]}
          label="Access"
          options={["timeseries", "histogram", "table"]}
        />

        <.input type="textarea" id="input-parameters" field={@form[:parameters]} label="Parameters" />
        <.selectors_input form={@form} />
        <.required_selectors_input form={@form} />
        <.button phx-disable-with="Saving...">Save</.button>
      </.simple_form>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :text, :string, required: true
  attr :icon, :string, required: false, default: nil
  attr :fp, :map, required: false, default: nil

  def inputs_for_button(assigns) do
    ~H"""
    <label class="block cursor-pointer">
      <input :if={@fp} type="checkbox" name={@name} value={@fp.index} class="hidden" />
      <input :if={!@fp} type="checkbox" name={@name} class="hidden" />

      <div class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center">
        <.icon :if={@icon} name={@icon} class="w-6 h-6 relative bg-red-800" />
        <%= @text %>
      </div>
    </label>
    """
  end

  def inputs_for_drop_button(assigns) do
    ~H"""
    <label class="cursor-pointer">
      <input type="checkbox" name={@name} value={@fp.index} class="hidden" />

      <div class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center">
        <.icon name="hero-x-mark" class="w-6 h-6 relative bg-red-800" /> <%= @text %>
      </div>
    </label>
    """
  end

  def aliases_input(assigns) do
    ~H"""
    <h3>Aliases</h3>
    <.inputs_for :let={fp} field={@form[:aliases]}>
      <.input field={fp[:name]} type="text" label="Alias" />

      <.inputs_for_drop_button fp={fp} name="registry[aliases_drop][]" text="Remove alias" />
    </.inputs_for>

    <label class="block cursor-pointer">
      <div class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center">
        <input type="checkbox" name="registry[aliases_sort][]" class="hidden" /> Add new alias
      </div>
    </label>
    """
  end

  def tables_input(assigns) do
    ~H"""
    <h3>Tables</h3>
    <.inputs_for :let={fp} field={@form[:tables]}>
      <.input field={fp[:name]} type="text" label="Table" />

      <.inputs_for_drop_button fp={fp} name="registry[tables_drop][]" text="Remove table" />
    </.inputs_for>

    <label class="block cursor-pointer">
      <div class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center">
        <input type="checkbox" name="registry[tables_sort][]" class="hidden" /> Add new table
      </div>
    </label>
    """
  end

  def selectors_input(assigns) do
    ~H"""
    <h3>Selectors</h3>
    <.inputs_for :let={fp} field={@form[:selectors]}>
      <.input field={fp[:type]} type="text" label="Selector" />

      <.inputs_for_drop_button fp={fp} name="registry[selectors_drop][]" text="Remove selector" />
    </.inputs_for>

    <label class="block cursor-pointer">
      <div class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center">
        <input type="checkbox" name="registry[selectors_sort][]" class="hidden" /> Add new selector
      </div>
    </label>
    """
  end

  def required_selectors_input(assigns) do
    ~H"""
    <h3>Required Selectors</h3>
    <.inputs_for :let={fp} field={@form[:required_selectors]}>
      <.input field={fp[:type]} type="text" label="Required Selector" />

      <.inputs_for_drop_button
        fp={fp}
        name="registry[required_selectors_drop][]"
        text="Remove required_selector"
      />
    </.inputs_for>

    <label class="block cursor-pointer">
      <div class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center">
        <input type="checkbox" name="registry[required_selectors_sort][]" class="hidden" />
        Add new required selector
      </div>
    </label>
    """
  end

  def handle_event("save", %{"registry" => params}, socket)
      when socket.assigns.live_action == :new do
    case socket.assigns.form.errors do
      [] ->
        :ok

      [_ | _] ->
        :ok
    end
  end

  @impl true
  def handle_event("save", %{"registry" => params}, socket)
      when socket.assigns.live_action == :edit do
    case socket.assigns.form.errors do
      [] ->
        case Registry.update(socket.assigns.metric_registry, params) do
          {:ok, metric_registry} ->
            {:noreply,
             socket
             |> assign(metric_registry: metric_registry)
             |> put_flash(:info, "Metric registry updated")
             |> push_navigate(to: ~p"/metric_registry/show/#{metric_registry.id}")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to update metric registry")}
        end

      [_ | _] = errors ->
        {:noreply,
         socket
         |> put_flash(:error, "Address field validation errors before saving: #{inspect(errors)}")}
    end
  end

  @impl true
  def handle_event("validate", %{"registry" => params}, socket) do
    # with {:ok, params} <- process_params(params) do
    IO.inspect(params)

    form =
      socket.assigns.metric_registry
      |> Registry.changeset(params)
      |> to_form(action: :validate)

    {:noreply, socket |> assign(form: form)}
    # else
    #   _ -> {:noreply, socket}
    # end
  end

  defp process_params(params) do
    {:ok, params}
    |> maybe_update_if_present("parameters")
    |> maybe_update_if_present("table")
  end

  defp maybe_update_if_present({:ok, %{"parameters" => _} = params}, "parameters") do
    case Jason.decode(params["parameters"]) do
      {:ok, decoded} -> {:ok, %{params | "parameters" => decoded}}
      {:error, _} -> {:ok, params}
    end
  end

  defp maybe_update_if_present({:ok, %{"table" => _} = params}, "table") do
    {:ok, %{params | "table" => List.wrap(params["table"])}}
  end

  defp maybe_update_if_present({:ok, params}, _), do: {:ok, params}
  defp maybe_update_if_present({:error, error}, _), do: {:error, error}

  defp page_title(:new), do: "Create new metric"
  defp page_title(:edit), do: "Edit a metric"
end
