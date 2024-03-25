defmodule SanbaseWeb.AdminFormsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.Admin.UserSubmissionAdminComponents

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
    <UserSubmissionAdminComponents.forms_list_container>
      <UserSubmissionAdminComponents.forms_list_title title="Admin Forms" />
      <UserSubmissionAdminComponents.form_info
        :for={form_info <- @forms_info}
        title={form_info.title}
        description={form_info.description}
        buttons={form_info.buttons}
      />
    </UserSubmissionAdminComponents.forms_list_container>
    """
  end

  defp get_forms_info() do
    [
      %{
        title: "Monitored Twitter Handle Submissions",
        description: """
        Approve or decline submissions for new Twitter handles to be monitored, suggested by users.
        """,
        buttons: [
          %{url: ~p"/admin2/monitored_twitter_handle_live", text: "Open"}
        ]
      },
      %{
        title: "Ecosystem Asset Labels Change Submissions",
        description: """
        Approve or decline submissions for changes to the list of ecosystems for each asset
        """,
        buttons: [
          %{url: ~p"/admin2/add_ecosystems_labels_admin_live", text: "Open"}
        ]
      },
      %{
        title: "Image Uploader",
        description: """
        Upload an image that can be used for avatars, project logos, etc.
        """,
        buttons: [
          %{url: ~p"/admin2/upload_image_live", text: "Upload an image"},
          %{url: ~p"/admin2/uploaded_images", text: "List uploads"}
        ]
      }
    ]
  end
end
