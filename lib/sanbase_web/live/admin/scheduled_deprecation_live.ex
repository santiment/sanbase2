defmodule SanbaseWeb.ScheduledDeprecationLive do
  use SanbaseWeb, :live_view
  require Logger
  import SanbaseWeb.CoreComponents
  import Phoenix.HTML
  import PhoenixHTMLHelpers.Tag

  alias Sanbase.Notifications.DeprecationTemplates
  alias Sanbase.TemplateEngine
  alias Sanbase.DateTimeUtils
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <h1 class="text-gray-800 text-2xl">{@page_title}</h1>

      <.simple_form for={@form} id="deprecation-form" phx-change="validate" phx-submit="save">
        <.inputs_for :let={f} field={@form[:data]}>
          <h2 class="text-lg font-semibold mt-6 mb-3 border-b pb-2">Scheduling & Common Details</h2>
          <.input
            id={f[:scheduled_at].id}
            name={f[:scheduled_at].name}
            value={f[:scheduled_at].value}
            type="date"
            label="Deprecation Date"
            required
            outer_div_class="w-1/4"
            errors={@save_errors[:scheduled_at] || []}
          />
          <.input
            field={f[:contact_list]}
            type="select"
            label="Send To"
            options={@contact_lists}
            required
            errors={@save_errors[:contact_list] || []}
          />

          <%= for var <- @common_vars do %>
            <% key_str = var.key %>
            <% field_proxy = f[key_str] %>
            <.input
              id={field_proxy.id}
              name={field_proxy.name}
              value={field_proxy.value}
              type="text"
              label={var.label}
              required
              placeholder={if var.type == :list, do: "Comma-separated URLs"}
              errors={@save_errors[String.to_atom(key_str)] || []}
            />
          <% end %>

          <%= for step <- [:schedule, :reminder, :executed] do %>
            <.render_step
              step={step}
              templates={@templates}
              main_form={f}
              form={f[step]}
              preview={@previews[step]}
            />
          <% end %>
        </.inputs_for>

        <.button type="submit" phx-disable-with="Scheduling...">Schedule Notifications</.button>
      </.simple_form>
    </div>
    """
  end

  defp render_step(assigns) do
    %{step: step, templates: templates, main_form: main_form, form: step_form, preview: preview} =
      assigns

    config = templates[step]

    ~H"""
    <div class="mt-8 border border-gray-200 rounded-lg p-4 mb-6">
      <h2 class="text-xl font-semibold capitalize mb-4 border-b pb-2">
        Step: {step} Notification
        <span :if={step == :reminder} class="text-sm text-gray-500 font-normal">
          (Sent 3 days before)
        </span>
        <span :if={step == :executed} class="text-sm text-gray-500 font-normal">
          (Sent on deprecation date)
        </span>
      </h2>

      <.inputs_for :let={sf} field={step_form}>
        <.input
          field={sf[:subject]}
          type="text"
          label="Email Subject"
          value={sf[:subject].value || config.default_subject}
          required
        />
      </.inputs_for>

      <div :if={preview} class="mt-6 border-t pt-4">
        <h3 class="text-md font-semibold mb-2">Preview Details</h3>

        <p class="text-sm text-gray-600 mb-3">
          Will be sent on
          <span class="font-semibold">
            {render_send_date(step, main_form[:scheduled_at].value)}
          </span>
          to list:
          <span class="font-semibold">
            {main_form[:contact_list].value}
          </span>
        </p>

        <p><strong>Subject:</strong> {preview.subject}</p>
        <p class="mt-2"><strong>Body:</strong></p>
        <iframe class="w-full h-64 border border-gray-300 rounded" srcdoc={preview.body_html} />
      </div>
    </div>
    """
  end

  defp render_send_date(step, scheduled_at_str) do
    case Date.from_iso8601(scheduled_at_str) do
      {:ok, scheduled_date} ->
        send_date =
          case step do
            :reminder -> Date.add(scheduled_date, -3)
            _ -> scheduled_date
          end

        format_date(Date.to_iso8601(send_date))

      _ ->
        format_date(scheduled_at_str)
    end
  end

  @impl true
  def handle_event("validate", %{"deprecation" => %{"data" => data}}, socket) do
    templates = socket.assigns.templates
    common_vars = socket.assigns.common_vars
    form = to_form(%{"data" => data}, as: :deprecation, action: :validate)

    common_data_filled? =
      !is_nil_or_empty?(data["scheduled_at"]) and
        Enum.all?(common_vars, &(!is_nil_or_empty?(data[&1.key])))

    errors = validate_data(data)

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
     |> assign(
       form: form,
       previews: previews,
       save_errors: errors
     )}
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

    {:safe, list_iodata} =
      content_tag(:ul, class: "list-disc list-inside ml-4") do
        Enum.map(links_list, fn link ->
          content_tag(:li, content_tag(:a, link, href: link, target: "_blank"))
        end)
      end

    engine_params = Map.put(engine_params, "links_html", IO.iodata_to_binary(list_iodata))

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
  rescue
    e ->
      Logger.error("Error generating preview for #{step}: #{inspect(e)}")
      nil
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
        %{links: ["cannot be blank"]}

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
end
