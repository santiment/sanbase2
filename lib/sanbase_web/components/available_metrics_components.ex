defmodule SanbaseWeb.AvailableMetricsComponents do
  use Phoenix.Component

  import SanbaseWeb.CoreComponents

  attr :text, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, default: nil

  def available_metrics_button(assigns) do
    ~H"""
    <.link
      href={@href}
      class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
    >
      <.icon :if={@icon} name={@icon} class="text-gray-500" />
      <%= @text %>
    </.link>
    """
  end
end
