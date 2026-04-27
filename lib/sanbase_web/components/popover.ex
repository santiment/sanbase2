defmodule SanbaseWeb.PopoverComponent do
  @moduledoc """
  Reusable hover popover backed by DaisyUI `dropdown`. Smart-aligns
  horizontally on hover so the body never overflows the viewport, and the
  width is responsive: capped at `max_width` but always shrinking to fit
  the screen.

  ## Slots

    * `:trigger` (required) — the element the user hovers/focuses
    * default inner block — the popover body

  ## Examples

      <.popover id="docs-help" placement="bottom">
        <:trigger>Sync Status</:trigger>
        <p>Whether the metric has been deployed to production.</p>
      </.popover>

      <.popover id="metric" placement="right" max_width="40rem">
        <:trigger><span class="link">Open</span></:trigger>
        <pre>{@docs}</pre>
      </.popover>
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :placement, :string, default: "right", values: ~w(top bottom left right)
  attr :max_width, :string, default: "860px", doc: "max popover width (any CSS length)"
  attr :class, :string, default: nil, doc: "extra classes for the popover body"
  attr :trigger_class, :string, default: nil, doc: "extra classes for the trigger element"
  slot :trigger, required: true
  slot :inner_block, required: true

  def popover(assigns) do
    {placement_class, smart_align?} =
      case assigns.placement do
        "top" -> {"dropdown-top", true}
        "bottom" -> {"dropdown-bottom", true}
        "left" -> {"dropdown-left", false}
        "right" -> {"dropdown-right", false}
      end

    smart_mouseenter =
      "const r = $el.getBoundingClientRect();" <>
        " align = (r.left + r.width / 2 > window.innerWidth / 2) ? 'end' : 'start';"

    assigns =
      assigns
      |> assign(:placement_class, placement_class)
      |> assign(:smart_align?, smart_align?)
      |> assign(:smart_mouseenter, smart_mouseenter)
      |> assign(:width_style, "width: min(calc(100vw - 1rem), #{assigns.max_width});")

    ~H"""
    <div
      class={["dropdown dropdown-hover", @placement_class]}
      x-data={if @smart_align?, do: "{ align: 'start' }", else: "{}"}
      x-on:mouseenter={if @smart_align?, do: @smart_mouseenter}
      x-bind:class={if @smart_align?, do: "{ 'dropdown-end': align === 'end' }"}
    >
      <div tabindex="0" role="button" class={["cursor-help", @trigger_class]}>
        {render_slot(@trigger)}
      </div>

      <div
        id={@id}
        tabindex="0"
        style={@width_style}
        class={[
          "dropdown-content card card-sm bg-base-100 border border-base-300 shadow-2xl z-10 max-h-[min(80vh,580px)] overflow-y-auto px-8 py-6 text-sm font-medium text-base-content/70",
          @class
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
