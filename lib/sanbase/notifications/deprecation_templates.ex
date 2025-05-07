defmodule Sanbase.Notifications.DeprecationTemplates do
  # Define common vars expected at the top level
  def common_vars do
    [
      %{key: "api_endpoint", type: :string, label: "API Endpoint Name"},
      %{key: "links", type: :list, label: "Relevant Links (comma-separated)"}
      # scheduled_at and contact_list are handled separately
    ]
  end

  def templates do
    %{
      schedule: %{
        template_name: "api_endpoint_deprecation_scheduled",
        default_subject: "Deprecation of API endpoint '{{api_endpoint}}' scheduled",
        # Step-specific required vars (if any) could go here. None for now.
        required_vars: [],
        template_html: """
        <p>Hello,</p>
        <p>Please be advised that the API endpoint <strong>{{api_endpoint}}</strong> is scheduled for deprecation on <strong>{{scheduled_at_formatted}}</strong>.</p>
        <p>For more details, please visit:</p>
        {{links_html}}
        <p>Thank you,<br/>The Santiment Team</p>
        """
      },
      reminder: %{
        template_name: "api_endpoint_deprecation_reminder",
        default_subject: "Reminder: Deprecation of API endpoint '{{api_endpoint}}'",
        required_vars: [],
        template_html: """
        <p>Hello,</p>
        <p>This is a reminder that the API endpoint <strong>{{api_endpoint}}</strong> will be deprecated on <strong>{{scheduled_at_formatted}}</strong> (in 3 days).</p>
        <p>For more details, please visit:</p>
        {{links_html}}
        <p>Thank you,<br/>The Santiment Team</p>
        """
      },
      executed: %{
        template_name: "api_endpoint_deprecation_executed",
        default_subject: "API endpoint '{{api_endpoint}}' has been deprecated",
        required_vars: [],
        template_html: """
        <p>Hello,</p>
        <p>The API endpoint <strong>{{api_endpoint}}</strong> has now been deprecated as scheduled.</p>
        <p>Please refer to the following links for alternatives or documentation:</p>
        {{links_html}}
        <p>Thank you,<br/>The Santiment Team</p>
        """
      }
    }
  end
end
