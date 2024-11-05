defmodule SanbaseWeb.MetricRegistryEditLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents

  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, metric_registry} = Sanbase.Metric.Registry.by_id(id)

    form =
      metric_registry
      |> Sanbase.Metric.Registry.changeset(%{})
      |> to_form()

    {:ok,
     socket
     |> assign(
       metric_registry: metric_registry,
       form: form
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <h1 class="text-gray-800 text-2xl">
        Showing details for <span class="text-blue-700"><%= @metric_registry.metric %></span>
      </h1>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/metric_registry"}
          icon="hero-arrow-uturn-left"
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
        <!-- <.input type="text" id="input-table" field={@form[:table]} label="Table" /> -->
        <.input type="text" id="input-min-interval" field={@form[:min_interval]} label="Min Interval" />
        <.input
          type="select"
          id="input-aggregation"
          field={@form[:aggregation]}
          label="Default Aggregation"
          options={Sanbase.Metric.Registry.aggregations()}
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
          id="input-data-type"
          field={@form[:data_type]}
          label="Access"
          options={["timeseries", "histogram", "table"]}
        />

        <.input type="textarea" id="input-parameters" field={@form[:parameters]} label="Parameters" />

        <h3>Tables</h3>
        <.inputs_for :let={fp} field={@form[:tables]}>
          <.input field={fp[:name]} type="text" label="Table" />

          <label class="cursor-pointer">
            <input type="checkbox" name="registry[tables_drop][]" value={fp.index} class="hidden" />
            <.icon name="hero-x-mark" class="w-6 h-6 relative bg-red-800" /> Remove table
          </label>
        </.inputs_for>

        <label class="block cursor-pointer">
          <input type="checkbox" name="registry[tables_add][]" class="hidden" /> Add new table
        </label>
      </.simple_form>
    </div>
    """
  end

  def array_input(assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end

  @impl true
  def handle_event("save", %{"registry" => _params}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"registry" => params}, socket) do
    with {:ok, params} <- process_params(params) do
      form =
        socket.assigns.metric_registry
        |> Sanbase.Metric.Registry.changeset(params)
        |> to_form(action: :validate)

      {:noreply, socket |> assign(form: form)}
    else
      _ -> {:noreply, socket}
    end
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
end
