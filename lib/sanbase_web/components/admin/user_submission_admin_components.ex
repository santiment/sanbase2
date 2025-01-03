defmodule SanbaseWeb.AdminFormsComponents do
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
      {@status |> String.replace("_", " ") |> String.upcase()}
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
      {@display_text}
    </button>
    """
  end

  slot(:inner_block, required: true)

  def forms_list_container(assigns) do
    ~H"""
    <div class="flex flex-col border border-gray-100 mx-auto max-w-3xl p-6 rounded-xl shadow-sm divide-y divide-solid">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:title, :string, required: true)

  def forms_list_title(assigns) do
    ~H"""
    <h1 class="py-6 text-3xl font-extrabold leading-none tracking-tight text-gray-900">
      {@title}
    </h1>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:buttons, :list, required: true)

  def form_info(assigns) do
    ~H"""
    <div class="flex flex-col md:flex-row py-8 items-center justify-between">
      <!-- Title and description -->
      <div class="w-3/4">
        <span class="text-2xl mb-6">{@title}</span>
        <p class="text-sm text-gray-500">{@description}</p>
      </div>
      <!-- Link to form -->
      <div class="flex flex-col space-y-2 ">
        <.link :for={button <- @buttons} href={button.url} target="_blank">
          <button class="bg-blue-600 w-full px-6 hover:bg-blue-900 rounded-xl text-white py-2">
            {button.text}
          </button>
        </.link>
      </div>
    </div>
    """
  end

  defp status_to_color("approved"), do: "text-green-600"
  defp status_to_color("declined"), do: "text-red-600"
  defp status_to_color("pending_approval"), do: "text-yellow-600"
end
