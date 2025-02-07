defmodule Sanbase.Notifications.TemplateRenderer do
  alias Sanbase.TemplateEngine

  def render(template_id, params) do
    template = Sanbase.Notifications.get_notification_template!(template_id)
    {:ok, content} = TemplateEngine.run(template.template, params: params)
    String.trim(content)
  end

  def render_content(
        %{
          action: action,
          params: params,
          step: step,
          channel: channel
        } = data
      ) do
    mime_type = data[:mime_type] || "text/plain"
    # Convert template params keys to strings and handle list parameters
    params =
      Map.new(params, fn
        {key, value}
        when is_list(value) and
               key in ["metrics_list", "asset_categories", :metrics_list, :asset_categories] ->
          {to_string(key), Enum.join(value, ", ")}

        {k, v} ->
          {to_string(k), v}
      end)

    params = Map.put(params, "current_year", Date.utc_today().year)
    params = augment_params(params, "scheduled_at", &format_datetime/1)

    case Sanbase.Notifications.get_template(to_string(action), step, channel, mime_type) do
      nil ->
        raise "Template not found for #{action}/#{step}/#{channel}"

      template ->
        {:ok, content} = TemplateEngine.run(template.template, params: params)
        String.trim(content)
    end
  end

  def augment_params(params, param_key, augment_fn) when is_map(params) do
    case Map.get(params, param_key) do
      nil -> params
      value -> Map.put(params, param_key, augment_fn.(value))
    end
  end

  defp format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Sanbase.DateTimeUtils.to_human_readable(datetime)
      _ -> Sanbase.DateTimeUtils.to_human_readable(value)
    end
  end

  defp format_datetime(value) do
    Sanbase.DateTimeUtils.to_human_readable(value)
  end
end
