defmodule SanbaseWeb.FormsLive do
  use SanbaseWeb, :live_view

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
    <div class="border border-gray-100 mx-auto max-w-3xl p-6 rounded-xl shadow-sm">
      <h1 class="mb-6 text-3xl font-extrabold leading-none tracking-tight text-gray-900">
        Forms
      </h1>
      <.form_link
        :for={form_info <- @forms_info}
        title={form_info.title}
        description={form_info.description}
        link={form_info.link}
      />
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:link, :string, required: true)

  def form_link(assigns) do
    ~H"""
    <div class="flex flex-col md:flex-row not-last:border-b border-slate-300 not-last:mb-8 pb-8 items-center justify-between">
      <!-- Title and description -->
      <div class="w-3/4">
        <span class="text-2xl mb-6"><%= @title %></span>
        <p class="text-sm text-gray-500"><%= @description %></p>
      </div>
      <!-- Link to form -->
      <div>
        <button class="bg-blue-600 px-6 hover:bg-blue-900 rounded-xl text-white py-2">
          <.link href={@link} target="_blank"> Open </.link>
        </button>
      </div>
    </div>
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
        link: ~p"/admin2/add_ecosystems_labels_live"
      }
    ]
  end
end
