defmodule SanbaseWeb.MetricRegistryFormLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.Permissions
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(params, _session, socket) do
    update_change_request_id = params["update_change_request_id"]
    duplicate_metric_registry_id = params["duplicate_metric_registry_id"]
    live_action = socket.assigns.live_action

    # In case we are updating a change request, the changes need to be
    # compared against the original metric registry.
    # If we compare the new changes agaisnt the metric_registry computed below
    # with applied changes, the `old -> new` changes will be wrong
    {:ok, original_metric_registry} = get_metric_registry(socket, params)

    # If the update_change_request_id is present, we need to apply the changes
    # as this is actually editing a Change Request. The notes are not part of the
    # metric registry and need to be additionally added here
    {:ok, metric_registry, suggestion} =
      maybe_apply_change_request(original_metric_registry, params)

    form = metric_registry |> Registry.changeset(%{}) |> to_form()

    {:ok,
     socket
     |> assign(
       is_updating_change_request: not is_nil(update_change_request_id),
       update_change_request_id: update_change_request_id,
       is_duplicate_creation: not is_nil(duplicate_metric_registry_id) and live_action == :new,
       page_title: page_title(live_action, metric_registry, update_change_request_id),
       metric_registry: metric_registry,
       original_metric_registry: original_metric_registry,
       email: nil,
       suggestion: suggestion,
       notes: if(suggestion, do: suggestion.notes),
       form: form,
       save_errors: []
     )}
  end

  def get_metric_registry(socket, params) do
    live_action = socket.assigns.live_action
    duplicate_metric_registry_id = params["duplicate_metric_registry_id"]

    cond do
      not is_nil(duplicate_metric_registry_id) and live_action == :new ->
        Registry.by_id(duplicate_metric_registry_id)

      live_action == :new ->
        {:ok, %Registry{}}

      live_action == :edit ->
        Registry.by_id(Map.fetch!(params, "id"))
    end
  end

  defp maybe_apply_change_request(metric_registry, params) do
    update_change_request_id = params["update_change_request_id"]

    if is_nil(update_change_request_id) do
      {:ok, metric_registry, _suggestion = nil}
    else
      {:ok, suggestion} = Registry.ChangeSuggestion.by_id(update_change_request_id)
      changes = Registry.ChangeSuggestion.decode_changes(suggestion.changes)
      params = Registry.ChangeSuggestion.changes_to_changeset_params(metric_registry, changes)
      changeset = Registry.changeset(metric_registry, params)
      metric_registry_with_changes = Ecto.Changeset.apply_changes(changeset)
      {:ok, metric_registry_with_changes, suggestion}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <div class="text-gray-800 text-2xl">
        <div :if={@live_action == :edit and not @is_updating_change_request}>
          Edit <span class="text-blue-700">{@metric_registry.metric}</span>
        </div>

        <div :if={@live_action == :edit and @is_updating_change_request}>
          Edit Change Request #{@update_change_request_id} for metric
          <span class="text-blue-700">{@metric_registry.metric}</span>
        </div>
        <div
          :if={
            @live_action == :new and @is_duplicate_creation == false and
              not @is_updating_change_request
          }
          class="text-blue-700"
        >
          Creating a new metric
        </div>

        <div
          :if={
            @live_action == :new and @is_duplicate_creation == true and @is_updating_change_request
          }
          class="text-blue-700"
        >
          Duplicating the metric {@metric_registry.metric}
        </div>
        <div :if={@live_action == :new and @is_duplicate_creation == true} class="text-sm">
          Some of the pre-filled values must be changed
          so the new metric differs a little bit from the old one.
        </div>
      </div>

      <SanbaseWeb.MetricRegistryComponents.user_details
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
      />
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin/metric_registry"}
          icon="hero-home"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={@live_action == :edit}
          text="See Metric"
          href={~p"/admin/metric_registry/show/#{@metric_registry}"}
          icon="hero-arrow-right-circle"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:edit, roles: @current_user_role_names) and @live_action == :edit}
          text="Duplicate Metric"
          href={
            ~p"/admin/metric_registry/new?#{%{duplicate_metric_registry_id: @metric_registry.id}}"
          }
          icon="hero-document-duplicate"
        />
      </div>
      <div>
        <span :if={@email}>Submit channges as: <span class="font-bold">{@email}</span></span>
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
          type="select"
          id="input-status"
          field={@form[:status]}
          label="Status"
          options={Registry.allowed_statuses()}
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
            Extra Change Request details
          </span>

          <.input
            type="textarea"
            name="notes"
            value={@notes}
            label="Notes"
            placeholder="Explanation why the changes are submitted"
          />
          <.button phx-disable-with="Submitting...">Submit Change Request</.button>
        </div>
        <.error :for={{field, [reason]} <- @save_errors}>
          {to_string(field) <> ": " <> inspect(reason)}
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
  attr :ef, :map, required: false, default: nil

  def inputs_for_drop_button(assigns) do
    ~H"""
    <button
      type="button"
      class="mt-2.5 mr-2 bg-white border border-gray-300 hover:bg-gray-50  rounded-xl text-sm px-3 py-2.5 inline-flex items-center"
      name={@name}
      value={@ef.index}
      phx-click={JS.dispatch("change")}
    >
      <.icon name="hero-x-mark" class="w-4 h-4 text-red-700" />
    </button>
    """
  end

  attr :name, :string, required: true

  def inputs_for_add_button(assigns) do
    ~H"""
    <div>
      <button
        type="button"
        name={@name}
        value="new"
        phx-click={JS.dispatch("change")}
        class="mt-4 mr-2 bg-white border border-gray-300 hover:bg-gray-50 hover:text-gray-700 text-gray-600 font-semibold rounded-xl text-sm px-5 py-2.5 inline-flex items-center "
      >
        <.icon name="hero-plus-circle" class="w-4 h-4 text-gray-500 mr-2" />
        <!-- Update icon to 'plus' for 'Add' -->
      Add
      </button>
    </div>
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
        {Inflex.camelize(@plural)}
      </span>
      <.inputs_for :let={ef} field={@form[@form_field]}>
        <input type="hidden" name={"registry[#{@sort_param}][]"} value={ef.index} />
        <div class="flex flex-grow min-w-0 items-start">
          <.inputs_for_drop_button ef={ef} name={"registry[#{@drop_param}][]"} />
          <.input
            type="text"
            outer_div_class="flex-grow"
            field={ef[@embeded_schema_field]}
            placeholder={@placeholder || @singular}
          />
        </div>
      </.inputs_for>

      <input type="hidden" name={"registry[#{@drop_param}][]"} />

      <.inputs_for_add_button name={"registry[#{@sort_param}][]"} />
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

  @impl true
  def handle_event("save", %{"registry" => params, "notes" => notes}, socket)
      when socket.assigns.live_action == :edit and
             socket.assigns.is_updating_change_request == true do
    #
    # Edit a Change Request that updates an existing metric registry
    #
    Permissions.raise_if_cannot(:edit_change_suggestion,
      roles: socket.assigns.current_user_role_names,
      user_email: socket.assigns.current_user.email,
      submitter_email: socket.assigns.suggestion.submitted_by
    )

    case socket.assigns.form.errors do
      [] ->
        params = process_params(params)

        {:ok, suggestion} =
          Registry.ChangeSuggestion.by_id(socket.assigns.update_change_request_id)

        case Registry.ChangeSuggestion.update_change_suggestion(
               suggestion,
               socket.assigns.original_metric_registry,
               params,
               notes
             ) do
          {:ok, _change_suggestion} ->
            {:noreply,
             socket
             |> assign(save_errors: [])
             |> put_flash(:info, "Metric registry change request updated")
             |> push_navigate(to: ~p"/admin/metric_registry/change_suggestions/")}

          {:error, error} ->
            errors = Sanbase.Utils.ErrorHandling.changeset_errors(error)

            {:noreply,
             socket
             |> assign(:save_errors, errors)
             |> put_flash(:error, "Fix field validation errors before saving")}
        end

      [_ | _] = errors ->
        {:noreply,
         socket
         |> put_flash(:error, "Fix field validation errors before saving: #{inspect(errors)}")}
    end
  end

  @impl true
  def handle_event("save", %{"registry" => params, "notes" => notes}, socket)
      when socket.assigns.live_action == :new and
             socket.assigns.is_updating_change_request == true do
    #
    # Edit a Change Request that creates a new metric registry record
    #
    Permissions.raise_if_cannot(:edit_change_suggestion,
      roles: socket.assigns.current_user_role_names,
      user_email: socket.assigns.current_user.email,
      submitter_email: socket.assigns.suggestion.submitted_by
    )

    case socket.assigns.form.errors do
      [] ->
        params = process_params(params)

        {:ok, suggestion} =
          Registry.ChangeSuggestion.by_id(socket.assigns.update_change_request_id)

        case Registry.ChangeSuggestion.update_change_suggestion(
               suggestion,
               %Registry{id: nil},
               params,
               notes
             ) do
          {:ok, _change_suggestion} ->
            {:noreply,
             socket
             |> assign(save_errors: [])
             |> put_flash(:info, "Metric registry change request updated")
             |> push_navigate(to: ~p"/admin/metric_registry/change_suggestions/")}

          {:error, error} ->
            errors = Sanbase.Utils.ErrorHandling.changeset_errors(error)

            {:noreply,
             socket
             |> assign(:save_errors, errors)
             |> put_flash(:error, "Fix field validation errors before saving")}
        end

      [_ | _] = errors ->
        {:noreply,
         socket
         |> put_flash(:error, "Fix field validation errors before saving: #{inspect(errors)}")}
    end
  end

  def handle_event(
        "save",
        %{"registry" => params, "notes" => notes},
        socket
      )
      when socket.assigns.live_action == :new do
    Permissions.raise_if_cannot(:create, roles: socket.assigns.current_user_role_names)

    case socket.assigns.form.errors do
      [] ->
        params = process_params(params)

        case Registry.ChangeSuggestion.create_change_suggestion(
               %Registry{id: nil},
               params,
               notes,
               socket.assigns.current_user.email
             ) do
          {:ok, _change_suggestion} ->
            {:noreply,
             socket
             |> assign(save_errors: [])
             |> put_flash(:info, "Metric registry change request created")
             |> push_navigate(to: ~p"/admin/metric_registry/change_suggestions/")}

          {:error, %Ecto.Changeset{} = error} ->
            errors = Sanbase.Utils.ErrorHandling.changeset_errors(error)

            {:noreply,
             socket
             |> assign(:save_errors, errors)
             |> put_flash(:error, "Fix field validation errors before saving")}

          {:error, error} when is_binary(error) ->
            {:noreply,
             socket
             |> put_flash(:error, "Error creating change request: #{error}")}
        end

      [_ | _] = errors ->
        {:noreply,
         socket
         |> put_flash(:error, "Fix field validation errors before saving: #{inspect(errors)}")}
    end
  end

  def handle_event(
        "save",
        %{"registry" => params, "notes" => notes},
        socket
      )
      when socket.assigns.live_action == :edit do
    Permissions.raise_if_cannot(:edit, roles: socket.assigns.current_user_role_names)

    case socket.assigns.form.errors do
      [] ->
        params = process_params(params)

        case Registry.ChangeSuggestion.create_change_suggestion(
               socket.assigns.metric_registry,
               params,
               notes,
               socket.assigns.current_user.email
             ) do
          {:ok, _change_suggestion} ->
            {:noreply,
             socket
             |> put_flash(:info, "Metric registry change suggestion submitted")
             |> push_navigate(to: ~p"/admin/metric_registry/change_suggestions/")}

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
         |> put_flash(:error, "Fix field validation errors before saving: #{inspect(errors)}")}
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

  defp page_title(:new, _metric_registry, nil = _update_change_request_id),
    do: "Metric Registry | Create New Record"

  defp page_title(:edit, metric_registry, nil = _update_change_request_id),
    do: "Metric Registry | Edit #{metric_registry.metric}"

  defp page_title(:edit, metric_registry, update_change_request_id),
    do:
      "Metric Registry | Edit Change Request ##{update_change_request_id} for #{metric_registry.metric}"

  defp page_title(:new, metric_registry, update_change_request_id),
    do:
      "Metric Registry | Edit Change Request ##{update_change_request_id} for creating a new metric #{metric_registry.metric}"
end
