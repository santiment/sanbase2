defmodule SanbaseWeb.MetricRegistryComponents do
  @moduledoc """
  Shared UI components specific to the Metric Registry admin section.

  Contains components used across multiple metric registry LiveView pages
  but not generic enough for AdminSharedComponents.
  """
  use Phoenix.Component

  alias SanbaseWeb.CoreComponents

  # ---------------------------------------------------------------------------
  # Metric Names — displays metric/internal_metric/human_readable_name
  # Consolidates 2 copies from MetricRegistryIndexLive and MetricRegistrySyncLive
  # ---------------------------------------------------------------------------

  attr :metric, :string, required: true
  attr :internal_metric, :string, required: true
  attr :human_readable_name, :string, required: true
  attr :status, :string, default: nil
  attr :category_mappings, :list, default: []

  def metric_names(assigns) do
    ~H"""
    <div class="flex flex-col break-normal">
      <div class="text-black text-base">
        {@human_readable_name}
        <span
          :if={@status in ["alpha", "beta"]}
          class={if @status == "alpha", do: "text-amber-600 text-sm", else: "text-violet-600 text-sm"}
        >
          ({String.upcase(@status)})
        </span>
      </div>
      <div class="text-gray-900 text-sm">{@metric} (API)</div>
      <div class="text-gray-900 text-sm">{@internal_metric} (DB)</div>
      <div :if={@category_mappings != []} class="flex flex-wrap gap-1 mt-1">
        <span
          :for={category_mapping <- @category_mappings}
          class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800"
        >
          <CoreComponents.icon name="hero-tag" class="w-3 h-3 mr-1" />
          {category_mapping.category.name}<span :if={category_mapping.group}>/{category_mapping.group.name}</span>
        </span>
      </div>
    </div>
    """
  end

end
