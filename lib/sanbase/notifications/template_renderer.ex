defmodule Sanbase.Notifications.TemplateRenderer do
  alias Sanbase.TemplateEngine

  def render(template_id, params) do
    template = Sanbase.Notifications.get_notification_template!(template_id)
    {:ok, content} = TemplateEngine.run(template.template, params: params)
    String.trim(content)
  end

  def render_content(%{action: action, params: params, step: step, channel: channel} = data) do
    mime_type = data[:mime_type] || "text/plain"

    params = process_params(params, mime_type)
    params = Map.put(params, "current_year", Date.utc_today().year)
    params = augment_params(params, "scheduled_at", &format_datetime/1)

    template = get_template_or_raise(action, step, channel, mime_type)
    {:ok, content} = TemplateEngine.run(template.template, params: params)
    String.trim(content)
  end

  defp process_params(params, mime_type) do
    Map.new(params, fn
      {key, value} when is_list(value) and key in ["metrics_list", :metrics_list] ->
        {to_string(key), format_metrics_list(value, params, mime_type)}

      {key, value} when is_list(value) and key in ["asset_categories", :asset_categories] ->
        {to_string(key), join_with_commas(value)}

      {k, v} ->
        {to_string(k), v}
    end)
  end

  defp format_metrics_list(metrics, params, "text/html") do
    metrics_docs_map = Map.get(params, "metrics_docs_map", %{})

    metrics
    |> Enum.map(fn metric ->
      format_metric_with_html(to_string(metric), metrics_docs_map)
    end)
    |> Enum.join("")
  end

  defp format_metrics_list(metrics, _params, _mime_type) do
    join_with_commas(metrics)
  end

  defp format_metric_with_html(metric_name, metrics_docs_map) do
    doc_links = Map.get(metrics_docs_map, metric_name, [])
    doc_link_html = format_doc_link(doc_links)

    "<br/>• #{metric_name}#{doc_link_html}"
  end

  defp format_doc_link([]), do: ""
  defp format_doc_link([link | _]), do: " (<a href=\"#{link}\" target=\"_blank\">docs</a>)"

  defp join_with_commas(list) do
    list |> Enum.map(&to_string/1) |> Enum.join(", ")
  end

  defp get_template_or_raise(action, step, channel, mime_type) do
    case Sanbase.Notifications.get_template(to_string(action), step, channel, mime_type) do
      nil -> raise "Template not found for #{action}/#{step}/#{channel}"
      template -> template
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
