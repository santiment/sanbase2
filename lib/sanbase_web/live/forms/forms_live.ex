defmodule SanbaseWeb.FormsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.Admin.UserSubmissionAdminComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       page_title: "Santiment Forms",
       forms_info: get_forms_info()
     )}
  end

  def render(assigns) do
    ~H"""
    <UserSubmissionAdminComponents.forms_list_container>
      <UserSubmissionAdminComponents.forms_list_title title="Forms" />
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
        title: "Update the ecosystem labels of an asset",
        description: """
        Suggest changes to the ecosystem labels of an asset. One asset can have many ecosystems, which indicate which blockchain ecosystem this project contributes to.
        The ecosystems are used when computing metrics for whole ecosystems, like Development activity data per ecosystem.
        """,
        buttons: [%{url: ~p"/forms/suggest_ecosystems", text: "Open"}]
      }
    ]
  end
end
