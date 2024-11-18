defmodule Sanbase.Notifications.TemplateRenderer do
  alias Sanbase.TemplateEngine

  def render_content(
        %{
          action: action,
          params: params,
          step: step,
          channel: channel
        } = _data
      ) do
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

    case Sanbase.Notifications.get_template(to_string(action), step, channel) do
      nil ->
        raise "Template not found for #{action}/#{step}/#{channel}"

      template ->
        {:ok, content} = TemplateEngine.run(template.template, params: params)
        String.trim(content)
    end
  end
end
