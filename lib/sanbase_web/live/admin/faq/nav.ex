defmodule SanbaseWeb.Admin.FaqLive.Nav do
  @moduledoc """
  Shared top navigation across the FAQ admin pages so each page can reach the
  others. Import `nav/1` and render it at the top of the page with the current
  page marked active, e.g. `<.nav active={:ask} />`.
  """
  use SanbaseWeb, :html

  attr :active, :atom, required: true, doc: "current page: :index, :ask or :history"

  def nav(assigns) do
    ~H"""
    <nav class="border-b border-base-300 bg-base-100">
      <div class="max-w-7xl mx-auto px-6 h-14 flex items-center gap-6">
        <span class="font-semibold tracking-tight text-base-content/90 whitespace-nowrap">
          Knowledge Base
        </span>
        <div class="flex items-center gap-1">
          <.nav_link navigate={~p"/admin/faq"} icon="hero-document-text" active={@active == :index}>
            Entries
          </.nav_link>
          <.nav_link navigate={~p"/admin/faq/ask"} icon="hero-sparkles" active={@active == :ask}>
            Ask
          </.nav_link>
          <.nav_link navigate={~p"/admin/faq/history"} icon="hero-clock" active={@active == :history}>
            History
          </.nav_link>
        </div>
      </div>
    </nav>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg transition-colors",
        @active && "bg-primary/10 text-primary",
        !@active && "text-base-content/60 hover:text-base-content hover:bg-base-200"
      ]}
    >
      <.icon name={@icon} class="size-4" /> {render_slot(@inner_block)}
    </.link>
    """
  end
end
