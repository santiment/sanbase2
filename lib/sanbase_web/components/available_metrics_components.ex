defmodule SanbaseWeb.AvailableMetricsComponents do
  use Phoenix.Component

  alias SanbaseWeb.CoreComponents

  @doc ~s"""
  The styled button is used to link to documentation and
  to link to the details page. Supports icons on the left side.
  """
  attr :text, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, default: nil

  def available_metrics_button(assigns) do
    ~H"""
    <.link
      href={@href}
      class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
    >
      <CoreComponents.icon :if={@icon} name={@icon} class="text-gray-500" />
      <%= @text %>
    </.link>
    """
  end

  @doc ~s"""

  """
  attr :display_text, :string, required: true
  attr :popover_target, :string, required: true
  attr :popover_target_text, :string, required: true
  attr :popover_placement, :string, default: "right"
  attr :popover_class, :string, default: nil

  def popover(assigns) do
    ~H"""
    <div class="relative">
      <div
        data-popover-target={@popover_target}
        data-popover-style="light"
        data-popover-placement={@popover_placement}
      >
        <span class="border-b border-dotted border-gray-500 hover:cursor-help hover:text-blue-500 hover:border-blue-500">
          <%= @display_text %>
        </span>
      </div>

      <div
        id={@popover_target}
        role="tooltip"
        class={[
          "absolute max-h-[580px] min-w-[860px] overflow-y-auto z-10 invisible inline-block px-8 py-6 text-sm font-medium text-gray-600 bg-white border border-gray-200 rounded-lg shadow-2xl sans",
          @popover_class
        ]}
      >
        <span class="[&>pre]:font-sans"><%= @popover_target_text %></span>
      </div>
    </div>
    """
  end

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
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal">
              <.popover
                display_text={col[:label]}
                popover_target={col[:popover_target]}
                popover_target_text={col[:popover_target_text]}
                popover_placement={col[:popover_placement] || "bottom"}
                popover_class="min-w-[600px]"
              />
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", col[:col_class], @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def th(assigns) do
    ~H"""
    <th class="px-5 py-3 text-xs font-semibold tracking-wider text-left text-gray-600 uppercase bg-gray-100 border-b-2 border-gray-200">
      <%= @field %>
    </th>
    """
  end

  def td(assigns) do
    ~H"""
    <td class="px-5 py-5 text-sm bg-white border-b border-gray-200"><%= @value %></td>
    """
  end
end
