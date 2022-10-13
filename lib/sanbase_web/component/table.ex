defmodule SanbaseWeb.TableComponent do
  use Phoenix.Component

  def table(assigns) do
    ~H"""
    <div class="mt-6">
    <h3 class="text-3xl font-medium text-gray-700"><%= @model %></h3>
    <table class="table-auto border-collapse w-full mb-4">
      <thead>
        <tr class="rounded-lg text-sm font-medium text-gray-700 text-left" style="font-size: 0.9674rem">
          <%= for field <- @fields do %>
            <.th field={field} />
          <% end %>
        </tr>
      </thead>
      <tbody class="text-sm font-normal text-gray-700">
        <%= for row <- @rows do %>
          <tr class="hover:bg-gray-100 border-b border-gray-200 py-4">
            <%= for field <- @fields do %>
              <.td row={row} field={field} value={if @funcs[field] != nil, do: @funcs[field].(row), else: Map.get(row, field)}  />
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
    </div>
    """
  end

  def th(assigns) do
    ~H"""
    <th class="px-5 py-3 text-xs font-semibold tracking-wider text-left text-gray-600 uppercase bg-gray-100 border-b-2 border-gray-200"><%= @field %></th>
    """
  end

  def td(assigns) do
    ~H"""
    <td class="px-5 py-5 text-sm bg-white border-b border-gray-200"><%= @value %></td>
    """
  end
end
