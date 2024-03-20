defmodule SanbaseWeb.EcosystemComponents do
  @moduledoc """
  Provides core UI components.

  At the first glance, this module may seem daunting, but its goal is
  to provide some core building blocks in your application, such modals,
  tables, and forms. The components are mostly markup and well documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  attr(:ecosystems, :list, required: true)
  attr(:ecosystem_colors_class, :string, default: "bg-blue-100 text-blue-800")

  def ecosystems_group(assigns) do
    ~H"""
    <div class="flex flex-col md:flex-row gap-1 flex-wrap">
      <.ecosystem_span
        :for={ecosystem <- @ecosystems}
        ecosystem={ecosystem}
        class={@ecosystem_colors_class}
      />
    </div>
    """
  end

  attr(:ecosystem, :map, required: true)
  attr(:class, :string, required: false, default: nil)

  def ecosystem_span(assigns) do
    ~H"""
    <span class={[
      "text-md font-medium me-2 px-2.5 py-1 rounded",
      @class
    ]}>
      <%= @ecosystem %>
    </span>
    """
  end
end
