defmodule SanbaseWeb.Layouts do
  use SanbaseWeb, :html

  embed_templates("layouts/*")

  def theme_toggle(assigns) do
    ~H"""
    <label
      class="swap swap-rotate btn btn-ghost btn-circle"
      title="Toggle theme"
      aria-label="Toggle theme"
    >
      <input
        type="checkbox"
        class="theme-controller"
        value="dark"
        id="theme-controller"
      />
      <.icon name="hero-sun" class="swap-off size-5" />
      <.icon name="hero-moon" class="swap-on size-5" />
    </label>
    """
  end
end
