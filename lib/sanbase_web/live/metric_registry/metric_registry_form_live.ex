defmodule SanbaseWeb.MetricRegistryFormLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents

  alias Sanbase.Metric.Registry
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(params, session, socket) do
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
       email: get_email(session),
       page_title: page_title(socket.assigns.live_action, metric_registry.metric),
       form: form,
       save_errors: []
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
          href={~p"/admin2/metric_registry"}
          icon="hero-arrow-uturn-left"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={@live_action == :edit}
          text="See Metric"
          href={~p"/admin2/metric_registry/show/#{@metric_registry}"}
          icon="hero-arrow-right-circle"
        />
      </div>
      <div>
        <span :if={!!@email}>Submit channges as: <span class="font-bold"><%= @email %></span></span>
        <span :if={!@email}>
          If you want to label your change submission with your email,
          <.link
            class="text-blue-500 underline"
            href={SanbaseWeb.Endpoint.frontend_url()}
            target="_blank"
          >
            login to Sanbase!
          </.link>
        </span>
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
        <.min_plan_input form={@form} />
        <.input
          type="select"
          id="input-access"
          field={@form[:access]}
          label="Access"
          options={["free", "restricted"]}
        />
        <.input type="text" id="input-min-interval" field={@form[:min_interval]} label="Min Interval" />
        <.input
          type="select"
          id="input-default-aggregation"
          field={@form[:default_aggregation]}
          label="Default Aggregation"
          options={Registry.aggregations()}
        />

        <.input
          type="select"
          id="input-has-incomplete-data"
          field={@form[:has_incomplete_data]}
          label="Has Incomplete Data"
          options={[true, false]}
        />
        <.input
          type="select"
          id="input-exposed-environments"
          field={@form[:exposed_environments]}
          label="Exposed on Environments"
          options={["all", "none", "stage", "prod"]}
        />

        <.input
          type="select"
          id="input-data-type"
          field={@form[:data_type]}
          label="Data Type"
          options={["timeseries", "histogram", "table"]}
        />
        <.docs_input form={@form} />
        <.selectors_input form={@form} />
        <.required_selectors_input form={@form} />

        <.input
          type="select"
          id="input-is-hidden"
          field={@form[:is_hidden]}
          label="Is Hidden"
          options={[true, false]}
        />
        <.input
          type="select"
          id="input-is-timebound"
          field={@form[:is_timebound]}
          label="Is Timebound"
          options={[true, false]}
        />
        <.input
          type="textarea"
          id="input-parameters"
          field={@form[:parameters]}
          value={Jason.encode!(@metric_registry.parameters)}
          label="Parameters"
        />

        <.deprecation_input form={@form} />
        <div class="border border-gray-200 rounded-lg px-3 py-6 flex-row space-y-5">
          <span class="text-sm font-semibold leading-6 text-zinc-800">
            Extra Change Suggestion details
          </span>

          <.input
            type="textarea"
            name="notes"
            value=""
            label="Notes"
            placeholder="Explanation why the changes are submitted"
          />
          <.input
            type="text"
            label="Submitted by (prefilled if logged into Sanbase)"
            name="submitted_by"
            value={@email}
          />
          <.button phx-disable-with="Submitting...">Submit Change Suggestion</.button>
        </div>
        <.error :for={{field, [reason]} <- @save_errors}>
          <%= to_string(field) <> ": " <> inspect(reason) %>
        </.error>
      </.simple_form>
    </div>
    """
  end

  def deprecation_input(assigns) do
    assigns = assign(assigns, disabled: assigns.form[:is_deprecated].value in [false, "false"])

    ~H"""
    <div class="border border-gray-200 rounded-lg px-3 py-6">
      <.input
        type="select"
        id="input-is-deprecated"
        label="Is Deprecated"
        field={@form[:is_deprecated]}
        options={[true, false]}
      />
      <div class={["rounded-b-lg px-3 py-6", if(@disabled, do: "bg-gray-100")]}>
        <.input
          type="datetime-local"
          id="input-hard-deprecate-after"
          label="Hard Deprecate After"
          field={@form[:hard_deprecate_after]}
          disabled={@disabled}
          title={if @disabled, do: "Disabled until `Is Deprecated` is set to true"}
        />

        <.input
          type="textarea"
          id="input-deprecation-note"
          label="Deprecation Note"
          field={@form[:deprecation_note]}
          disabled={@disabled}
          placeholder={if @disabled, do: "Disabled until `Is Deprecated` is set to true"}
        />
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  def min_plan_input(assigns) do
    ~H"""
    <.input
      type="select"
      id="input-sanbase-min-plan"
      field={@form[:sanbase_min_plan]}
      label="Sanbase Min Plan"
      options={["free", "pro", "max"]}
    />

    <.input
      type="select"
      id="input-sanapi-min-plan"
      field={@form[:sanapi_min_plan]}
      label="Sanapi Min Plan"
      options={["free", "pro", "max"]}
    />
    """
  end

  attr :name, :string, required: true
  attr :text, :string, required: true
  attr :ef, :map, required: false, default: nil

  def inputs_for_drop_button(assigns) do
    ~H"""
    <button
      type="button"
      class="text-gray-900 my-1 bg-white hover:bg-red-100 border border-gray-200 font-medium rounded-lg text-sm px-4 py-2 text-center inline-flex items-center"
      name={@name}
      value={@ef.index}
      phx-click={JS.dispatch("change")}
    >
      <.icon name="hero-x-mark" class="w-6 h-6 relative bg-red-700" />
      <%= @text %>
    </button>
    """
  end

  attr :name, :string, required: true
  attr :text, :string, required: true

  def inputs_for_add_button(assigns) do
    ~H"""
    <hr class="h-px my-8 bg-gray-200 border-0 dark:bg-gray-700" />
    <button
      type="button"
      name={@name}
      value="new"
      phx-click={JS.dispatch("change")}
      class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center"
    >
      <%= @text %>
    </button>
    """
  end

  attr :form, :map, required: true
  attr :singular, :string, required: true
  attr :plural, :string, required: true
  attr :form_field, :atom, required: true
  attr :embeded_schema_field, :atom, required: true
  attr :sort_param, :atom, required: true
  attr :drop_param, :atom, required: true
  attr :placeholder, :string, required: false, default: nil

  def embeds_input(assigns) do
    ~H"""
    <div class="border border-gray-200 rounded-lg px-3 py-6">
      <span class="text-sm font-semibold leading-6 text-zinc-800">
        <%= Inflex.camelize(@plural) %>
      </span>
      <.inputs_for :let={ef} field={@form[@form_field]}>
        <input type="hidden" name={"registry[#{@sort_param}][]"} value={ef.index} />
        <.input type="text" field={ef[@embeded_schema_field]} placeholder={@placeholder || @singular} />

        <.inputs_for_drop_button
          ef={ef}
          name={"registry[#{@drop_param}][]"}
          text={"Remove #{@singular}"}
        />
      </.inputs_for>

      <input type="hidden" name={"registry[#{@drop_param}][]"} />

      <.inputs_for_add_button name={"registry[#{@sort_param}][]"} text={"Add new #{@singular}"} />
    </div>
    """
  end

  def aliases_input(assigns) do
    ~H"""
    <.embeds_input
      form={@form}
      plural="aliases"
      singular="alias"
      form_field={:aliases}
      embeded_schema_field={:name}
      sort_param={:aliases_sort}
      drop_param={:aliases_drop}
    />
    """
  end

  def tables_input(assigns) do
    ~H"""
    <.embeds_input
      form={@form}
      plural="tables"
      singular="table"
      form_field={:tables}
      embeded_schema_field={:name}
      sort_param={:tables_sort}
      drop_param={:tables_drop}
    />
    """
  end

  def docs_input(assigns) do
    ~H"""
    <.embeds_input
      form={@form}
      plural="docs"
      singular="doc"
      placeholder="https://academy.santiment.net/..."
      form_field={:docs}
      embeded_schema_field={:link}
      sort_param={:docs_sort}
      drop_param={:docs_drop}
    />
    """
  end

  def selectors_input(assigns) do
    ~H"""
    <.embeds_input
      form={@form}
      plural="selectors"
      singular="selector"
      form_field={:selectors}
      embeded_schema_field={:type}
      sort_param={:selectors_sort}
      drop_param={:selectors_drop}
    />
    """
  end

  def required_selectors_input(assigns) do
    ~H"""
    <.embeds_input
      form={@form}
      plural="required selectors"
      singular="required selector"
      form_field={:required_selectors}
      embeded_schema_field={:type}
      sort_param={:required_selectors_sort}
      drop_param={:required_selectors_drop}
    />
    """
  end

  def handle_event("save", %{"registry" => params}, socket)
      when socket.assigns.live_action == :new do
    case socket.assigns.form.errors do
      [] ->
        params = process_params(params)

        case Sanbase.Metric.Registry.create(params) do
          {:ok, struct} ->
            {:noreply,
             socket
             |> assign(save_errors: [])
             |> put_flash(:info, "Metric registry created")
             |> push_navigate(to: ~p"/admin2/metric_registry/show/#{struct}")}

          {:error, error} ->
            errors = Sanbase.Utils.ErrorHandling.changeset_errors(error)

            {:noreply,
             socket
             |> assign(:save_errors, errors)
             |> put_flash(:error, "Address field validation errors before saving")}
        end

      [_ | _] = errors ->
        {:noreply,
         socket
         |> put_flash(:error, "Address field validation errors before saving: #{inspect(errors)}")}
    end
  end

  def handle_event(
        "save",
        %{"registry" => params, "notes" => notes, "submitted_by" => submitted_by},
        socket
      )
      when socket.assigns.live_action == :edit do
    case socket.assigns.form.errors do
      [] ->
        params = process_params(params)

        case Registry.ChangeSuggestion.create_change_suggestion(
               socket.assigns.metric_registry,
               params,
               notes,
               submitted_by
             ) do
          {:ok, _change_suggestion} ->
            {:noreply,
             socket
             |> put_flash(:info, "Metric registry change suggestion submitted")
             |> push_navigate(to: ~p"/admin2/metric_registry/change_suggestions/")}

          {:error, changeset} ->
            errors = Sanbase.Utils.ErrorHandling.changeset_errors(changeset)
            require(IEx).pry

            {:noreply,
             socket
             |> assign(:save_errors, errors)
             |> put_flash(:error, "Failed to update metric registry")}
        end

      [_ | _] = errors ->
        {:noreply,
         socket
         |> put_flash(:error, "Address field validation errors before saving: #{inspect(errors)}")}
    end
  end

  @impl true
  def handle_event(
        "validate",
        %{"registry" => params},
        socket
      ) do
    params = process_params(params)

    form =
      socket.assigns.metric_registry
      |> Registry.changeset(params)
      |> to_form(action: :validate)

    {:noreply,
     socket
     |> assign(
       form: form,
       save_errors: []
     )}
  end

  defp process_params(params) do
    params
    |> maybe_update_if_present("parameters")
    |> maybe_update_if_present("fixed_parameters")
  end

  defp maybe_update_if_present(%{"parameters" => json} = params, "parameters") do
    # If the parameters are not valid JSON, we will keep the old parameters.
    # It will fail from the changeset validation with `invalid format`. If it is
    # valid JSON, replace the string with the decoded JSON and let the Ecto changeset
    # validate it further
    case Jason.decode(json) do
      {:ok, decoded} when is_list(decoded) -> %{params | "parameters" => decoded}
      {:error, _} -> params
    end
  end

  defp maybe_update_if_present(%{"fixed_parameters" => json} = params, "fixed_parameters") do
    # If the fixed_parameters are not valid JSON, we will keep the old fixed_parameters.
    # It will fail from the changeset validation with `invalid format`. If it is
    # valid JSON, replace the string with the decoded JSON and let the Ecto changeset
    # validate it further
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> %{params | "fixed_parameters" => decoded}
      {:error, _} -> params
    end
  end

  defp maybe_update_if_present(params, _), do: params

  defp page_title(:new, _), do: "Creating a new metric"
  defp page_title(:edit, metric), do: "#{metric} | Edit metric"

  # Get the email from the refresh token. The access token expires more quick
  # and we don't need to refresh it from here. We only need to get the email
  # of the santiment user in order to prefill some column showing who submits the
  # suggestion
  defp get_email(%{"refresh_token" => token}) when is_binary(token) do
    case SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, %{email: email}, _token_claims} when is_binary(email) -> email
      _ -> nil
    end
  end

  defp get_email(_), do: nil
end
