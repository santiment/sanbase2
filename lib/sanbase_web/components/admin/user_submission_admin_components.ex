defmodule SanbaseWeb.Admin.UserSubmissionAdminComponents do
  use Phoenix.Component

  @moduledoc ~s"""
  Components reused in the parts of the admin panel related to
  manually approvind/declining submissions sent by users.

  Such submissions include the MonitoredTwitterHandleLive and
  EcosystemLabelSubmissionsLive
  """

  attr(:status, :string, required: true)

  def status(assigns) do
    ~H"""
    <p class={status_to_color(@status)}>
      <%= @status |> String.replace("_", " ") |> String.upcase() %>
    </p>
    """
  end

  attr(:name, :string, required: true)
  attr(:value, :string, required: true)
  attr(:display_text, :string, required: true)
  attr(:class, :string, required: true)
  attr(:disabled, :boolean, default: false)

  def button(assigns) do
    ~H"""
    <button
      name={@name}
      value={@value}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg my-1 py-2 px-3 text-sm font-semibold leading-6 text-white",
        @class
      ]}
      disabled={@disabled}
    >
      <%= @display_text %>
    </button>
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

  defp status_to_color("approved"), do: "text-green-600"
  defp status_to_color("declined"), do: "text-red-600"
  defp status_to_color("pending_approval"), do: "text-yellow-600"
end
