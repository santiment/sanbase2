defmodule SanbaseWeb.Categorization.ReorderComponents do
  use Phoenix.Component
  import SanbaseWeb.CoreComponents

  @doc """
  Renders reorder controls with up/down arrow buttons.
  """
  attr :index, :integer, required: true
  attr :total_count, :integer, required: true
  attr :item_id, :any, required: true
  attr :display_order, :integer, required: true
  attr :event_prefix, :string, default: ""

  def reorder_controls(assigns) do
    ~H"""
    <div class="flex items-center">
      <button
        phx-click={"#{@event_prefix}move-up"}
        phx-value-id={@item_id}
        class="mr-2"
        disabled={@index == 0}
      >
        <.icon name="hero-arrow-up" class="w-4 h-4" />
      </button>
      <span>{@display_order}</span>
      <button
        phx-click={"#{@event_prefix}move-down"}
        phx-value-id={@item_id}
        class="ml-2"
        disabled={@index == @total_count - 1}
      >
        <.icon name="hero-arrow-down" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  @doc """
  Parses element IDs from drag-and-drop reorder events.
  Extracts numeric IDs from format like "prefix-123".
  """
  @spec parse_reorder_ids([String.t()], String.t()) :: [
          %{id: integer(), display_order: integer()}
        ]
  def parse_reorder_ids(ids, prefix) do
    ids
    |> Enum.with_index(1)
    |> Enum.map(fn {id, index} ->
      item_id = id |> String.replace("#{prefix}-", "") |> String.to_integer()
      %{id: item_id, display_order: index}
    end)
  end
end
