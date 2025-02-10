defmodule SanbaseWeb.FormsLive do
  @moduledoc false
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminFormsComponents

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
    <AdminFormsComponents.forms_list_container>
      <AdminFormsComponents.forms_list_title title="Forms" />
      <AdminFormsComponents.form_info
        :for={form_info <- @forms_info}
        title={form_info.title}
        description={form_info.description}
        buttons={form_info.buttons}
      />
    </AdminFormsComponents.forms_list_container>
    """
  end

  defp get_forms_info do
    [
      %{
        title: "Update the Ecosystem Labels of an asset",
        description: """
        Suggest changes to the ecosystem labels of an asset. One asset can have many ecosystems, which indicate which blockchain ecosystem this project contributes to.
        The ecosystems are used to compute metrics for whole ecosystems, like Development activity data per ecosystem.
        """,
        buttons: [%{url: ~p"/forms/suggest_ecosystems", text: "Open"}]
      },
      %{
        title: "Update the Github Organizations of an asset",
        description: """
        Suggest changes to the github organizations of an asset. One asset can have many github organizations where the development of the product happens.
        The github organizations are used to compute the Development Activity metrics..
        """,
        buttons: [%{url: ~p"/forms/suggest_github_organizations", text: "Open"}]
      }
    ]
  end
end
