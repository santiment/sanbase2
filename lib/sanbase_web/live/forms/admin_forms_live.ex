defmodule SanbaseWeb.AdminFormsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminFormsComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       page_title: "Admin Forms",
       forms_info: get_forms_info()
     )}
  end

  def render(assigns) do
    ~H"""
    <AdminFormsComponents.forms_list_container>
      <AdminFormsComponents.forms_list_title title="Admin Forms" />
      <AdminFormsComponents.form_info
        :for={form_info <- @forms_info}
        title={form_info.title}
        description={form_info.description}
        buttons={form_info.buttons}
      />
    </AdminFormsComponents.forms_list_container>
    """
  end

  defp get_forms_info() do
    [
      %{
        title: "Metric registry",
        description: """
        Manage the Clickhouse metrics exposed through the API
        """,
        buttons: [
          %{url: ~p"/admin/metric_registry", text: "Open"}
        ]
      },
      %{
        title: "Monitored Twitter Handle Submissions",
        description: """
        Approve or decline submissions for new Twitter handles to be monitored, suggested by users.
        """,
        buttons: [
          %{url: ~p"/admin/monitored_twitter_handle_live", text: "Open"}
        ]
      },
      %{
        title: "Ecosystem Asset Labels Change Submissions",
        description: """
        Approve or decline submissions for changes to the list of ecosystems for an asset
        """,
        buttons: [
          %{url: ~p"/admin/suggest_ecosystems_admin_live", text: "Open"}
        ]
      },
      %{
        title: "Github Organizations Asset Change Submissions",
        description: """
        Approve or decline submissions for changes to the list of github organizations for an asset
        """,
        buttons: [
          %{url: ~p"/admin/suggest_github_organizations_admin_live", text: "Open"}
        ]
      },
      %{
        title: "Image Uploader",
        description: """
        Upload an image that can be used for avatars, project logos, etc.
        """,
        buttons: [
          %{url: ~p"/admin/upload_image_live", text: "Upload an image"},
          %{url: ~p"/admin/uploaded_images_live", text: "List uploads"}
        ]
      },
      %{
        title: "Manual Notifications",
        description: """
        Send a manual notification to Discord or email
        """,
        buttons: [
          %{url: ~p"/admin/notifications/manual/discord", text: "Discord"},
          %{url: ~p"/admin/notifications/manual/email", text: "Email"}
        ]
      }
    ]
  end
end
