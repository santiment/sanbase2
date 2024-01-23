defmodule SanbaseWeb.TableComponent do
  use Phoenix.Component
  use Phoenix.HTML

  alias SanbaseWeb.Router.Helpers, as: Routes

  def table(assigns) do
    ~H"""
    <.search resource={@resource} search_value="" />

    <div class="mt-6">
      <h3 class="text-3xl font-medium text-gray-700"><%= @model %></h3>
      <table class="table-auto border-collapse w-full mb-4">
        <thead>
          <tr
            class="rounded-lg text-sm font-medium text-gray-700 text-left"
            style="font-size: 0.9674rem"
          >
            <%= for field <- @fields do %>
              <.th field={field} />
            <% end %>
            <.th field="Actions" />
          </tr>
        </thead>
        <tbody class="text-sm font-normal text-gray-700">
          <%= for row <- @rows do %>
            <tr class="hover:bg-gray-100 border-b border-gray-200 py-4">
              <%= for field <- @fields do %>
                <.td value={
                  if @funcs[field] != nil, do: @funcs[field].(row), else: Map.get(row, field)
                } />
              <% end %>
              <td class="px-5 py-5 text-sm bg-white border-b border-gray-200">
                <%= for action <- @actions do %>
                  <.a resource={@resource} action={action} row={row} /> |
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>

      <SanbaseWeb.PaginationComponent.pagination
        resource={@resource}
        rows_count={@rows_count}
        page_size={@page_size}
        current_page={@current_page}
        action={@action}
        search_text={@search_text}
      />
    </div>
    """
  end

  def a(assigns) do
    ~H"""
    <.link
      href={Routes.generic_path(SanbaseWeb.Endpoint, @action, @row, resource: @resource)}
      class="underline"
    >
      <%= Atom.to_string(@action) %>
    </.link>
    """
  end

  def search(assigns) do
    ~H"""
    <div class="relative mx-4 lg:mx-0">
      <span class="absolute inset-y-0 left-0 flex items-center pl-3">
        <svg class="w-5 h-5 text-gray-500" viewBox="0 0 24 24" fill="none">
          <path
            d="M21 21L15 15M17 10C17 13.866 13.866 17 10 17C6.13401 17 3 13.866 3 10C3 6.13401 6.13401 3 10 3C13.866 3 17 6.13401 17 10Z"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
          </path>
        </svg>
      </span>
      <.form
        :let={f}
        method="get"
        for={%{}}
        as={:search}
        action={Routes.generic_path(SanbaseWeb.Endpoint, :search, resource: @resource)}
      >
        <%= hidden_input(f, :resource, value: @resource) %>
        <%= text_input(f, :generic_search,
          value: @search_value,
          class:
            "w-32 pl-10 pr-4 text-indigo-600 border-gray-200 rounded-md sm:w-64 focus:border-indigo-600 focus:ring focus:ring-opacity-40 focus:ring-indigo-500"
        ) %>
        <%= submit("Search") %>
      </.form>
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

defmodule SanbaseWeb.PaginationComponent do
  use Phoenix.Component

  alias SanbaseWeb.Router.Helpers, as: Routes

  def pagination(assigns) do
    ~H"""
    <div class="flex justify-between items-center p-4">
      <.pagination_buttons
        resource={@resource}
        rows_count={@rows_count}
        page_size={@page_size}
        current_page={@current_page}
        action={@action}
        search_text={@search_text}
      />
      <span class="text-sm text-gray-700">
        Showing <%= @current_page * @page_size + 1 %> to <%= Enum.min([
          (@current_page + 1) * @page_size,
          @rows_count
        ]) %> of <%= @rows_count %> entries
      </span>
    </div>
    """
  end

  def pagination_buttons(assigns) do
    ~H"""
    <div class="inline-flex">
      <%= unless @current_page == 0 do %>
        <.link
          href={pagination_path(@resource, @action, @search_text, @current_page - 1)}
          class="px-4 py-2 mx-1 bg-gray-200 rounded hover:bg-gray-300"
        >
          Previous
        </.link>
      <% end %>
      <%= unless @current_page >= div(@rows_count - 1, @page_size) do %>
        <.link
          href={pagination_path(@resource, @action, @search_text, @current_page + 1)}
          class="px-4 py-2 mx-1 bg-gray-200 rounded hover:bg-gray-300"
        >
          Next
        </.link>
      <% end %>
    </div>
    """
  end

  defp pagination_path(resource, action, search_text, page_number) do
    case action do
      :index ->
        Routes.generic_path(SanbaseWeb.Endpoint, action, %{resource: resource, page: page_number})

      :search ->
        Routes.generic_path(SanbaseWeb.Endpoint, action, %{
          "resource" => resource,
          "page" => page_number,
          "search" => %{
            "generic_search" => search_text,
            "resource" => resource,
            "page" => page_number
          }
        })
    end
  end
end
