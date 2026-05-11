defmodule SanbaseWeb.AvailableMetricsComponents do
  use Phoenix.Component

  alias SanbaseWeb.CoreComponents
  alias SanbaseWeb.PopoverComponent

  @doc ~s"""
  The styled button is used to link to documentation and
  to link to the details page. Supports icons on the left side.
  """
  attr :text, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, default: nil
  attr :disabled, :boolean, default: false

  def available_metrics_button(assigns) do
    ~H"""
    <.link
      href={@href}
      class={[
        if(@disabled,
          do: "pointer-events-none bg-base-200 text-base-content/40",
          else: "bg-base-100 hover:bg-base-200 text-base-content"
        ),
        "border border-base-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
      ]}
    >
      <CoreComponents.icon :if={@icon} name={@icon} class="text-base-content/60" />
      {@text}
    </.link>
    """
  end

  @doc ~s"""
  Thin wrapper over `SanbaseWeb.PopoverComponent.popover/1` for the
  AvailableMetrics tables. When `popover_target_text` is blank the trigger
  is rendered as plain text — no popover.
  """
  attr :display_text, :string, required: true
  attr :popover_target, :string, required: true
  attr :popover_target_text, :any, default: nil
  attr :popover_placement, :string, default: "right"
  attr :popover_class, :string, default: nil

  def popover(assigns) do
    if popover_text?(assigns.popover_target_text) do
      ~H"""
      <PopoverComponent.popover
        id={@popover_target}
        placement={@popover_placement}
        class={@popover_class}
      >
        <:trigger>
          <span class="border-b border-dotted border-base-content/40 hover:text-primary hover:border-primary">
            {@display_text}
          </span>
        </:trigger>
        <span class="[&>pre]:font-sans">{@popover_target_text}</span>
      </PopoverComponent.popover>
      """
    else
      ~H"<span>{@display_text}</span>"
    end
  end

  defp popover_text?(nil), do: false
  defp popover_text?(text) when is_binary(text), do: String.trim(text) != ""
  defp popover_text?(_), do: false

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  slot :col, required: true do
    attr(:label, :string)
    attr(:col_class, :string)
    attr(:popover_target, :string)
    attr(:popover_target_text, :string)
    attr(:popover_placement, :string)
  end

  slot(:action, doc: "the slot for showing user actions in the last table column")

  def table_with_popover_th(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-base-content/60">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal">
              <.popover
                display_text={col[:label]}
                popover_target={col[:popover_target]}
                popover_target_text={col[:popover_target_text]}
                popover_placement={col[:popover_placement] || "bottom"}
              />
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-base-300 border-t border-base-300 text-sm leading-6 text-base-content/80"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-base-200">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", col[:col_class], @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 px-6">
                <span class={[
                  "absolute -inset-y-px right-0 left-0 group-hover:bg-base-200",
                  i == 0 && "-left-8 sm:rounded-l-xl",
                  i == length(@col) - 1 && @action == [] && "-right-8 sm:rounded-r-xl"
                ]} />
                <span class={["relative", i == 0 && "text-base-content"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-8 left-0 group-hover:bg-base-200 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-base-content hover:text-base-content/70"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
