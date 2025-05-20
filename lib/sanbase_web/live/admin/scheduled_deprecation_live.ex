defmodule SanbaseWeb.ScheduledDeprecationLive do
  use SanbaseWeb, :live_view
  require Logger
  import SanbaseWeb.CoreComponents
  import PhoenixHTMLHelpers.Tag

  alias Sanbase.Notifications.DeprecationTemplates
  alias Sanbase.TemplateEngine
  alias Sanbase.Validation
  alias Timex

  @contact_lists ["API Users Only", "API & Sanbase Users - Metric Updates"]

  @impl true
  def mount(_params, _session, socket) do
    templates = DeprecationTemplates.templates()
    common_vars = DeprecationTemplates.common_vars()
    form_data = initialize_form_data(templates, common_vars, @contact_lists)

    form = to_form(%{"data" => form_data}, as: :deprecation)

    {:ok,
     socket
     |> assign(
       page_title: "Schedule API Endpoint Deprecation Notification",
       templates: templates,
       common_vars: common_vars,
       form_data: form_data,
       form: form,
       previews: %{schedule: nil, reminder: nil, executed: nil},
       contact_lists: @contact_lists,
       save_errors: []
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <div class="mb-4">
        <.link
          href="/admin/scheduled_deprecations"
          class="text-blue-600 hover:underline flex items-center"
        >
          <.icon name="hero-arrow-left" class="h-4 w-4 mr-1" /> Back to Scheduled Deprecations
        </.link>
      </div>
      <h1 class="text-gray-800 text-2xl">{@page_title}</h1>

      <.simple_form for={@form} id="deprecation-form" phx-change="validate" phx-submit="save">
        <.inputs_for :let={f} field={@form[:data]}>
          <.common_details_form
            form={f}
            save_errors={@save_errors}
            contact_lists={@contact_lists}
            common_vars={@common_vars}
          />

          <.step_notification_form
            :for={step <- [:schedule, :reminder, :executed]}
            step={step}
            templates={@templates}
            main_form={f}
            form={f[step]}
            preview={@previews[step]}
          />
        </.inputs_for>

        <.button type="submit" phx-disable-with="Scheduling...">Schedule Notifications</.button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"deprecation" => %{"data" => data}}, socket) do
    templates = socket.assigns.templates
    form = to_form(%{"data" => data}, as: :deprecation, action: :validate)

    api_endpoint_filled? = !is_nil_or_empty?(data["api_endpoint"])
    errors = validate_data(data)

    previews =
      if api_endpoint_filled? and errors == %{} do
        %{
          schedule: generate_preview(:schedule, data, templates),
          reminder: generate_preview(:reminder, data, templates),
          executed: generate_preview(:executed, data, templates)
        }
      else
        %{schedule: nil, reminder: nil, executed: nil}
      end

    {:noreply,
     socket
     |> assign(
       form: form,
       previews: previews,
       save_errors: errors
     )}
  end

  @impl true
  def handle_event("save", %{"deprecation" => %{"data" => data}}, socket) do
    templates = socket.assigns.templates
    common_vars = socket.assigns.common_vars

    errors = validate_data(data)

    if Enum.empty?(errors) do
      case generate_all_email_contents(data, templates, common_vars) do
        {:ok, email_contents} ->
          attrs_for_context = %{
            deprecation_date: data["scheduled_at"],
            contact_list_name: data["contact_list"],
            api_endpoint: data["api_endpoint"],
            links: String.split(data["links"] || "", ",", trim: true),
            schedule_email_subject: email_contents.schedule.subject,
            schedule_email_html: email_contents.schedule.body_html,
            reminder_email_subject: email_contents.reminder.subject,
            reminder_email_html: email_contents.reminder.body_html,
            executed_email_subject: email_contents.executed.subject,
            executed_email_html: email_contents.executed.body_html
          }

          case Sanbase.Notifications.create_scheduled_deprecation(attrs_for_context) do
            {:ok, _notification} ->
              new_form_data =
                initialize_form_data(templates, common_vars, socket.assigns.contact_lists)

              form = to_form(%{"data" => new_form_data}, as: :deprecation)

              {:noreply,
               socket
               |> assign(
                 form: form,
                 form_data: new_form_data,
                 previews: %{schedule: nil, reminder: nil, executed: nil},
                 save_errors: []
               )
               |> put_flash(:info, "Deprecation notification scheduled successfully!")}

            {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
              Logger.error("Failed to schedule deprecation (changeset): #{inspect(changeset)}")

              {:noreply,
               socket
               |> put_flash(
                 :error,
                 "Failed to schedule deprecation: #{inspect(changeset.errors)}"
               )}

            {:error, reason} ->
              Logger.error("Failed to schedule deprecation: #{inspect(reason)}")

              {:noreply,
               socket
               |> put_flash(:error, "Failed to schedule deprecation. Error: #{inspect(reason)}")}
          end

        {:error, {step, reason}} ->
          Logger.error("Failed to generate email content for step '#{step}': #{inspect(reason)}")

          {:noreply,
           socket
           |> put_flash(
             :error,
             "Failed to generate email content for step '#{step}'. Cannot schedule."
           )}
      end
    else
      form = to_form(%{"data" => data}, as: :deprecation, action: :validate)

      common_data_filled? =
        !is_nil_or_empty?(data["scheduled_at"]) and
          Enum.all?(common_vars, &(!is_nil_or_empty?(data[&1.key])))

      previews =
        if common_data_filled? and errors == %{} do
          %{
            schedule: generate_preview(:schedule, data, templates),
            reminder: generate_preview(:reminder, data, templates),
            executed: generate_preview(:executed, data, templates)
          }
        else
          %{schedule: nil, reminder: nil, executed: nil}
        end

      {:noreply,
       socket
       |> assign(form: form, save_errors: errors, previews: previews)
       |> put_flash(:error, "Please correct the errors below.")}
    end
  end

  defp generate_preview(step, data, templates) do
    step_config = templates[step]
    step_data = data[Atom.to_string(step)]
    scheduled_at_str = data["scheduled_at"]

    api_endpoint = data["api_endpoint"]
    links_str = data["links"]
    subject_template = step_data["subject"] || step_config.default_subject

    engine_params = %{
      "api_endpoint" => api_endpoint
    }

    formatted_date =
      case Date.from_iso8601(scheduled_at_str) do
        {:ok, date} -> Timex.format!(date, "%Y-%m-%d", :strftime)
        _ -> "(invalid date)"
      end

    engine_params = Map.put(engine_params, "scheduled_at_formatted", formatted_date)

    links_list = String.split(links_str || "", ",", trim: true)
    links_html = links_html_for_step(step, links_list)
    engine_params = Map.put(engine_params, "links_html", links_html)

    case {TemplateEngine.run(subject_template, params: engine_params),
          TemplateEngine.run(step_config.template_html, params: engine_params)} do
      {{:ok, subject}, {:ok, body_html}} ->
        %{subject: subject, body_html: body_html}

      {{:error, err}, _} ->
        Logger.error("Template engine error (#{step} subject): #{inspect(err)}")
        nil

      {_, {:error, err}} ->
        Logger.error("Template engine error (#{step} body): #{inspect(err)}")
        nil
    end
  end

  attr :form, :map, required: true
  attr :save_errors, :map, required: true
  attr :contact_lists, :list, required: true
  attr :common_vars, :list, required: true

  def common_details_form(assigns) do
    assigns =
      assign(
        assigns,
        :placeholders,
        Enum.into(assigns.common_vars, %{}, fn var -> {var.key, get_var_placeholder(var)} end)
      )

    ~H"""
    <h2 class="text-lg font-semibold mt-6 mb-3 border-b pb-2">Scheduling & Common Details</h2>
    <.input
      id={@form[:scheduled_at].id}
      name={@form[:scheduled_at].name}
      value={@form[:scheduled_at].value}
      type="date"
      label="Deprecation Date"
      required
      outer_div_class="w-1/4"
      errors={@save_errors[:scheduled_at] || []}
    />
    <.input
      field={@form[:contact_list]}
      type="select"
      label="Send To"
      options={@contact_lists}
      required
      errors={@save_errors[:contact_list] || []}
    />
    <.input
      :for={var <- @common_vars}
      id={@form[var.key].id}
      name={@form[var.key].name}
      value={@form[var.key].value}
      type="text"
      label={var.label}
      placeholder={@placeholders[var.key]}
      errors={@save_errors[String.to_atom(var.key)] || []}
    />
    """
  end

  attr :step, :atom, required: true
  attr :scheduled_at, :string, required: true
  attr :contact_list, :string, required: true
  attr :preview, :map, required: true

  def step_preview(assigns) do
    ~H"""
    <div class="mt-6 border-t pt-4">
      <h3 class="text-md font-semibold mb-2">Preview Details</h3>
      <p class="text-sm text-gray-600 mb-3">
        Will be sent on
        <span class="font-semibold">
          {render_send_date(@step, @scheduled_at)}
        </span>
        to list:
        <span class="font-semibold">
          {@contact_list}
        </span>
      </p>
      <p><strong>Subject:</strong> {@preview.subject}</p>
      <p class="mt-2"><strong>Body:</strong></p>
      <iframe class="w-full h-64 border border-gray-300 rounded" srcdoc={@preview.body_html} />
    </div>
    """
  end

  attr :step, :atom, required: true
  attr :templates, :map, required: true
  attr :main_form, :map, required: true
  attr :form, :map, required: true
  attr :preview, :map, required: false

  def step_notification_form(assigns) do
    config = assigns.templates[assigns.step]
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="mt-8 border border-gray-200 rounded-lg p-4 mb-6">
      <h2 class="text-xl font-semibold capitalize mb-4 border-b pb-2">
        Step: {@step} Notification
        <span :if={@step == :reminder} class="text-sm text-gray-500 font-normal">
          (Sent 3 days before)
        </span>
        <span :if={@step == :executed} class="text-sm text-gray-500 font-normal">
          (Sent on deprecation date)
        </span>
      </h2>

      <.inputs_for :let={sf} field={@form}>
        <.input
          field={sf[:subject]}
          type="text"
          label="Email Subject"
          value={sf[:subject].value || @config.default_subject}
          required
        />
      </.inputs_for>

      <.step_preview
        :if={@preview}
        step={@step}
        scheduled_at={@main_form[:scheduled_at].value}
        contact_list={@main_form[:contact_list].value}
        preview={@preview}
      />
    </div>
    """
  end

  defp render_send_date(:schedule, _scheduled_at_str) do
    format_date(Date.to_iso8601(Date.utc_today()))
  end

  defp render_send_date(:reminder, scheduled_at_str) do
    case Date.from_iso8601(scheduled_at_str) do
      {:ok, scheduled_date} ->
        send_date = Date.add(scheduled_date, -3)
        format_date(Date.to_iso8601(send_date))

      _ ->
        format_date(scheduled_at_str)
    end
  end

  defp render_send_date(:executed, scheduled_at_str) do
    format_date(scheduled_at_str)
  end

  defp links_html_for_step(step, links_list) do
    if Enum.any?(links_list) do
      intro =
        case step do
          :executed ->
            "<p>Please refer to the following links for alternatives or documentation:</p>"

          _ ->
            "<p>For more details, please visit:</p>"
        end

      {:safe, list_iodata} =
        content_tag(:ul, class: "list-disc list-inside ml-4") do
          Enum.map(links_list, fn link ->
            content_tag(:li, content_tag(:a, link, href: link, target: "_blank"))
          end)
        end

      intro <> IO.iodata_to_binary(list_iodata)
    else
      ""
    end
  end

  defp validate_data(data) do
    scheduled_at_str = data["scheduled_at"]
    api_endpoint_str = data["api_endpoint"]
    links_str = data["links"]

    date_errors = validate_scheduled_at_data(scheduled_at_str)
    endpoint_errors = validate_api_endpoint_data(api_endpoint_str)
    link_errors = validate_links_data(links_str)

    [date_errors, endpoint_errors, link_errors]
    |> Enum.reduce(%{}, fn error_map, acc ->
      Map.merge(acc, error_map)
    end)
  end

  defp validate_scheduled_at_data(scheduled_at_str) do
    cond do
      is_nil_or_empty?(scheduled_at_str) ->
        %{scheduled_at: ["cannot be blank"]}

      true ->
        case Date.from_iso8601(scheduled_at_str) do
          {:ok, scheduled_date} ->
            today = Date.utc_today()
            min_date = Date.add(today, 5)

            if Date.compare(scheduled_date, min_date) == :lt do
              %{scheduled_at: ["Deprecation date must be at least 5 days in the future"]}
            else
              %{}
            end

          {:error, _} ->
            %{scheduled_at: ["is not a valid date"]}
        end
    end
  end

  defp validate_api_endpoint_data(api_endpoint_str) do
    if is_nil_or_empty?(api_endpoint_str) do
      %{api_endpoint: ["cannot be blank"]}
    else
      %{}
    end
  end

  defp validate_links_data(links_str) do
    cond do
      is_nil_or_empty?(links_str) ->
        %{}

      true ->
        invalid_links =
          links_str
          |> String.split(~r/\s*,\s*/, trim: true)
          |> Enum.reject(fn link ->
            case Validation.valid_url?(link, require_path: false) do
              :ok -> true
              {:error, _reason} -> false
            end
          end)

        if Enum.empty?(invalid_links) do
          %{}
        else
          error_msg = "Invalid URL(s): #{Enum.join(invalid_links, ", ")}"
          %{links: [error_msg]}
        end
    end
  end

  defp is_nil_or_empty?(nil), do: true
  defp is_nil_or_empty?(""), do: true
  defp is_nil_or_empty?(_), do: false

  defp format_date(nil), do: "(not set)"

  defp format_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Timex.format!(date, "%d %b %Y", :strftime)
      _ -> "(invalid date)"
    end
  end

  defp generate_all_email_contents(data, templates, _common_vars) do
    with {:ok, schedule_content} <- generate_email_content_for_save(:schedule, data, templates),
         {:ok, reminder_content} <- generate_email_content_for_save(:reminder, data, templates),
         {:ok, executed_content} <- generate_email_content_for_save(:executed, data, templates) do
      {:ok,
       %{
         schedule: schedule_content,
         reminder: reminder_content,
         executed: executed_content
       }}
    else
      err -> err
    end
  end

  defp generate_email_content_for_save(step, data, templates) do
    step_config = templates[step]
    step_data = data[Atom.to_string(step)]
    scheduled_at_str = data["scheduled_at"]

    api_endpoint = data["api_endpoint"]
    links_str = data["links"]
    subject_template = step_data["subject"] || step_config.default_subject

    engine_params = %{
      "api_endpoint" => api_endpoint
    }

    formatted_date =
      case Date.from_iso8601(scheduled_at_str) do
        {:ok, date} -> Timex.format!(date, "%Y-%m-%d", :strftime)
        _ -> "(invalid date)"
      end

    engine_params = Map.put(engine_params, "scheduled_at_formatted", formatted_date)

    links_list = String.split(links_str || "", ",", trim: true)
    links_html = links_html_for_step(step, links_list)
    engine_params = Map.put(engine_params, "links_html", links_html)

    case {TemplateEngine.run(subject_template, params: engine_params),
          TemplateEngine.run(step_config.template_html, params: engine_params)} do
      {{:ok, subject}, {:ok, body_html}} ->
        {:ok, %{subject: subject, body_html: body_html}}

      {{:error, err}, _} ->
        Logger.error("Template engine error for SAVE (#{step} subject): #{inspect(err)}")
        {:error, {step, :template_error_subject}}

      {_, {:error, err}} ->
        Logger.error("Template engine error for SAVE (#{step} body): #{inspect(err)}")
        {:error, {step, :template_error_body}}
    end
  end

  defp initialize_form_data(templates, common_vars, contact_lists) do
    common_data =
      Enum.into(common_vars, %{}, fn var ->
        {var.key, if(var.type == :list, do: "", else: "")}
      end)

    step_data =
      Enum.into(templates, %{}, fn {step, config} ->
        {step, %{subject: config.default_subject, params: %{}}}
      end)

    %{scheduled_at: nil, contact_list: List.first(contact_lists)}
    |> Map.merge(common_data)
    |> Map.merge(step_data)
  end

  defp get_var_placeholder(var) do
    if var.type == :list, do: "Comma-separated URLs", else: nil
  end
end
