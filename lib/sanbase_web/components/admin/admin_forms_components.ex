defmodule SanbaseWeb.AdminFormsComponents do
  use Phoenix.Component

  @moduledoc ~s"""
  Components for the admin and user-facing forms listing pages.
  """

  slot(:inner_block, required: true)

  def forms_list_container(assigns) do
    ~H"""
    <div class="flex flex-col border border-base-300 bg-base-100 mx-auto max-w-3xl p-6 rounded-xl shadow-sm divide-y divide-base-300">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:title, :string, required: true)

  def forms_list_title(assigns) do
    ~H"""
    <h1 class="py-6 text-3xl font-extrabold leading-none tracking-tight text-base-content">
      {@title}
    </h1>
    """
  end

  @doc """
  One card in a forms listing: a title, a description and the action buttons for it.

  The card always renders a DOM id, so anything selecting a single card (a test, an
  anchor link) has a stable handle: `:id` when the caller passes one, otherwise one
  derived from the title.
  """
  attr(:id, :string, default: nil)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:buttons, :list, required: true)

  def form_info(assigns) do
    assigns = assign(assigns, :id, assigns.id || "form-info-" <> slug(assigns.title))

    ~H"""
    <div id={@id} class="flex flex-col md:flex-row py-8 items-center justify-between">
      <!-- Title and description -->
      <div class="w-3/4">
        <span class="text-2xl mb-6 text-base-content">{@title}</span>
        <p class="text-sm text-base-content/60">{@description}</p>
      </div>
      <!-- Link to form -->
      <div class="flex flex-col space-y-2 ">
        <.link :for={button <- @buttons} href={button.url} target="_blank">
          <button class="btn btn-primary w-full px-6">
            {button.text}
          </button>
        </.link>
      </div>
    </div>
    """
  end

  # The card's DOM id comes from its title so tests (and anything else selecting one
  # card) have a stable handle without every call site passing an id.
  defp slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
