defmodule Sanbase.Notifications.TemplateRenderer do
  alias Sanbase.Notifications.{Notification, NotificationAction}
  alias Sanbase.TemplateEngine

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :manual},
        content: content
      })
      when is_binary(content) do
    String.trim(content)
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: action_type},
        step: step,
        template_params: template_params
      }) do
    channel = "all"
    # Convert template params keys to strings and handle list parameters
    params =
      Map.new(template_params, fn
        {key, value}
        when is_list(value) and
               key in ["metrics_list", "asset_categories", :metrics_list, :asset_categories] ->
          {to_string(key), Enum.join(value, ", ")}

        {k, v} ->
          {to_string(k), v}
      end)

    case Sanbase.Notifications.get_template(to_string(action_type), to_string(step), channel) do
      nil ->
        raise "Template not found for #{action_type}/#{step}/#{channel}"

      template ->
        {:ok, content} = TemplateEngine.run(template.template, params: params)
        String.trim(content)
    end
  end
end
