defmodule SanbaseWeb.TableComponent do
  use Phoenix.Component
  use Phoenix.HTML

  import SanbaseWeb.CoreComponents

  alias SanbaseWeb.Router.Helpers, as: Routes

  def form_table(assigns) do
    ~H"""
    <div class="mt-6 p-4">
      <h3 class="text-3xl font-medium text-gray-700">
        <%= "#{String.capitalize(@type)} #{@resource}" %>
      </h3>
      <.form
        method={if @type == "new", do: "post", else: "patch"}
        for={@changeset}
        as={@resource}
        action={@action}
      >
        <%= if @changeset.action do %>
          <.form_error changeset={@changeset} />
        <% end %>

        <%= for field <- @form_fields do %>
          <div class="m-4">
            <%= if @belongs_to_fields[field] || @collections[field] do %>
              <% belongs_to = if @belongs_to_fields[field], do: true, else: false %>
              <.form_select
                type={@type}
                resource={@resource}
                field={field}
                changeset={@changeset}
                options={@belongs_to_fields[field] || @collections[field]}
                belongs_to={belongs_to}
              />
            <% else %>
              <.form_input
                type={@type}
                resource={@resource}
                field={field}
                changeset={@changeset}
                field_type_map={@field_type_map}
                data={@data}
              />
            <% end %>
          </div>
        <% end %>

        <.form_nav type={@type} resource={@resource} action={@action} />
      </.form>
    </div>
    """
  end

  def form_nav(assigns) do
    ~H"""
    <div class="flex justify-end">
      <.back_btn2 resource={@resource} action={:index} />
      <.button type="submit" class="mt-4 p-4">
        <%= if @type == "new", do: "Create", else: "Update" %>
      </.button>
    </div>
    """
  end

  def form_error(assigns) do
    ~H"""
    <div class="alert alert-danger">
      <p>Oops, something went wrong! Please check the errors below:</p>
      <ul>
        <%= for {attr, message} <- Ecto.Changeset.traverse_errors(@changeset, &translate_error/1) do %>
          <li class="text-red-500">
            <.icon name="hero-exclamation-circle-mini" class="mr-2" />
            <%= humanize(attr) %>: <%= Enum.join(message, ", ") %>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  def form_input(assigns) do
    ~H"""
    <.input
      name={@resource <> "[" <> to_string(@field) <> "]"}
      id={@resource <> "_" <> to_string(@field)}
      label={humanize(@field)}
      type={
        case Map.get(@field_type_map, @field) do
          :string -> "text"
          :text -> "textarea"
          :integer -> "number"
          :float -> "number"
          :boolean -> "checkbox"
          :date -> "text"
          :datetime -> "text"
          :time -> "text"
          :map -> "text"
          :list -> "text"
          :assoc -> "text"
          :binary -> "text"
          :any -> "text"
          _ -> "text"
        end
      }
      value={
        if @type == "new" do
          ""
        else
          case Map.get(@field_type_map, @field) do
            map_or_list when map_or_list in [:map, :list] ->
              Map.get(@changeset.data, @field) |> Jason.encode!()

            _ ->
              Map.get(@changeset.changes, @field) || Map.get(@changeset.data, @field) ||
                Map.get(@data, @field)
          end
        end
      }
    />
    """
  end

  def form_select(assigns) do
    ~H"""
    <.input
      name={
        if @belongs_to do
          @resource <> "[" <> to_string(@field) <> "_id" <> "]"
        else
          @resource <> "[" <> to_string(@field) <> "]"
        end
      }
      id={@resource <> "_" <> to_string(@field)}
      label={humanize(@field)}
      type="select"
      options={@options}
      value={
        field = if @belongs_to, do: String.to_existing_atom(to_string(@field) <> "_id"), else: @field

        if @type == "new" do
          if @changeset.changes[field] do
            @changeset.changes[field]
          else
            nil
          end
        else
          Map.get(@changeset.changes, field) || Map.get(@changeset.data, field)
        end
      }
      prompt={
        if length(@options) == 1,
          do: nil,
          else: "Select #{humanize(@field)}"
      }
    />
    """
  end

  def back_btn(assigns) do
    ~H"""
    <a
      href="javascript:history.back()"
      class="phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80 mt-4 mr-2"
    >
      Back
    </a>
    """
  end

  def back_btn2(assigns) do
    ~H"""
    <a
      href={Routes.generic_path(SanbaseWeb.Endpoint, @action, resource: @resource)}
      class="phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80 mt-4 mr-2"
    >
      Back
    </a>
    """
  end

  def link_btn(assigns) do
    ~H"""
    <a
      href={@href}
      class="phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80 mt-4 mr-2"
    >
      <%= @text %>
    </a>
    """
  end

  def show_table(assigns) do
    ~H"""
    <div class="mt-6">
      <h3 class="text-3xl font-medium text-gray-700">Show <%= Inflex.singularize(@resource) %></h3>
      <div class="table-responsive">
        <table class="table-auto border-collapse w-full mb-4 mt-4 text-sm">
          <tbody class="text-sm font-normal text-gray-700">
            <%= for field <- @fields do %>
              <tr class="hover:bg-gray-100 border border-gray-200 py-2">
                <.th class="px-2" field={to_string(field)} />
                <.td
                  class="px-2"
                  value={
                    result =
                      if @assocs[@data.id][field],
                        do: @assocs[@data.id][field],
                        else: Map.get(@data, field)

                    result =
                      if @funcs[field] != nil, do: @funcs[field].(@data), else: result

                    case Map.get(@field_type_map, field) do
                      :map ->
                        Jason.encode!(result)

                      :list ->
                        Jason.encode!(result)

                      :boolean ->
                        if result == true,
                          do: ~H|<span class="hero-check-circle text-green-500" />|,
                          else: ~H|<span class="hero-x-circle text-red-500" />|

                      _ ->
                        result
                    end
                  }
                />
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  def table(assigns) do
    ~H"""
    <div class="table-responsive">
      <div>
        <.search2 fields={@fields} resource={@resource} search_text={@search_text} />

        <%= if :new in @actions do %>
          <.link
            href={Routes.generic_path(SanbaseWeb.Endpoint, :new, resource: @resource)}
            class="underline relative mx-4 lg:mx-0 m-4 p-4"
          >
            New <%= Inflex.singularize(@resource) %>
          </.link>
        <% end %>
      </div>

      <div class="m-4">
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
                  <%= if field == :id do %>
                    <td class="px-5 py-5 text-sm bg-white border-b border-gray-200">
                      <.a resource={@resource} action={:show} row={row} label={Map.get(row, field)} />
                    </td>
                  <% else %>
                    <.td value={
                      result =
                        if @assocs[row.id][field],
                          do: @assocs[row.id][field],
                          else: Map.get(row, field)

                      result =
                        if @funcs[field] != nil, do: @funcs[field].(row), else: result

                      case Map.get(@field_type_map, field) do
                        :boolean ->
                          if result == true,
                            do: ~H|<span class="hero-check-circle text-green-500" />|,
                            else: ~H|<span class="hero-x-circle text-red-500" />|

                        _ ->
                          result
                      end
                    } />
                  <% end %>
                <% end %>
                <td class="px-5 py-5 text-sm bg-white border-b border-gray-200">
                  <% index_actions = @actions -- [:new] %>
                  <%= for {action, index} <- Enum.with_index(index_actions) do %>
                    <.a resource={@resource} action={action} row={row} label={action} />
                    <%= if index < length(index_actions) - 1, do: raw(" | ") %>
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
    </div>
    """
  end

  def has_many_table(assigns) do
    ~H"""
    <div class="mt-6">
      <h3 class="text-3xl font-medium text-gray-700"><%= @resource_name %></h3>
      <%= if @create_link_kv != [] do %>
        <.link
          href={
            Routes.generic_path(
              SanbaseWeb.Endpoint,
              :new,
              Keyword.merge([resource: @resource], @create_link_kv)
            )
          }
          class="underline relative lg:mx-0 mt-4 mb-4 pt-4 pb-4"
        >
          New <%= Inflex.singularize(@resource_name) %>
        </.link>
      <% end %>
      <table class="table-auto border-collapse w-full mb-4">
        <thead>
          <tr
            class="rounded-lg text-sm font-medium text-gray-700 text-left"
            style="font-size: 0.9674rem"
          >
            <%= for field <- @fields do %>
              <.th field={field} />
            <% end %>
          </tr>
        </thead>
        <tbody class="text-sm font-normal text-gray-700">
          <%= for row <- @rows do %>
            <tr class="hover:bg-gray-100 border-b border-gray-200 py-4">
              <%= for field <- @fields do %>
                <%= if field == :id do %>
                  <td class="px-5 py-5 text-sm bg-white border-b border-gray-200">
                    <.a resource={@resource} action={:show} row={row} label={Map.get(row, field)} />
                  </td>
                <% else %>
                  <.td
                    row={row}
                    field={field}
                    value={
                      if @funcs[field] != nil, do: @funcs[field].(row), else: Map.get(row, field)
                    }
                  />
                <% end %>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  def a(assigns) do
    ~H"""
    <.link
      href={Routes.generic_path(SanbaseWeb.Endpoint, @action, @row, resource: @resource)}
      class="underline"
    >
      <%= @label %>
    </.link>
    """
  end

  attr(:placeholder, :string, default: "Search...")
  attr(:resource, :string, required: true)
  attr(:search_value, :string, required: true)
  attr(:text_input_title, :string, default: "")

  def search(assigns) do
    ~H"""
    <div class="relative mx-4 lg:mx-0 m-4 p-4">
      <.icon
        name="hero-magnifying-glass"
        class="absolute left-5 top-1/2 transform -translate-y-1/2 text-gray-400"
      />
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
            "w-full xl:w-96 sm:w-64 pl-8 pr-4 text-indigo-600 border-gray-200 rounded-md focus:border-indigo-600 focus:ring focus:ring-opacity-40 focus:ring-indigo-500",
          placeholder: @placeholder,
          title: @text_input_title
        ) %>
        <.button type="submit" class="mt-4 p-4">Search</.button>
      </.form>
    </div>
    """
  end

  def search2(assigns) do
    ~H"""
    <div x-data="{ open: false, selectedField: 'Fields' }">
      <.form
        method="get"
        action={Routes.generic_path(SanbaseWeb.Endpoint, :search, resource: @resource)}
        class="max-w-lg mx-auto mt-2"
      >
        <input type="hidden" name="field" x-bind:value="selectedField" />
        <input type="hidden" name="resource" value={@resource} />
        <div class="flex">
          <button
            @click="open = !open"
            id="dropdown-button"
            class="flex-shrink-0 z-10 inline-flex items-center py-2.5 px-4 text-sm font-medium text-center text-gray-900 bg-gray-100 border border-gray-300 rounded-s-lg hover:bg-gray-200 focus:ring-4 focus:outline-none focus:ring-gray-100 dark:bg-gray-700 dark:hover:bg-gray-600 dark:focus:ring-gray-700 dark:text-white dark:border-gray-600"
            type="button"
          >
            <div class="flex items-center">
              <span x-text="selectedField"></span>
              <svg
                class="w-2.5 h-2.5 ms-2.5"
                aria-hidden="true"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 10 6"
              >
                <path
                  stroke="currentColor"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="m1 1 4 4 4-4"
                />
              </svg>
            </div>
          </button>
          <div
            x-show="open"
            @click.away="open = false"
            id="dropdown"
            class="mt-12 absolute z-20 bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700"
          >
            <ul
              class="py-2 text-sm text-gray-700 dark:text-gray-200"
              aria-labelledby="dropdown-button"
            >
              <%= for field <- @fields do %>
                <li>
                  <button
                    @click="selectedField = $event.target.innerText; open = false"
                    type="button"
                    class="inline-flex w-full px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    <%= field %>
                  </button>
                </li>
              <% end %>
            </ul>
          </div>
          <div class="relative w-full">
            <input
              name="value"
              type="search"
              id="search-dropdown"
              class="block p-2.5 w-full z-20 text-sm text-gray-900 bg-gray-50 rounded-e-lg border-s-gray-50 border-s-2 border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-s-gray-700  dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:border-blue-500"
              placeholder="Search ..."
              required
            />
            <button
              type="submit"
              class="absolute top-0 end-0 p-2.5 text-sm font-medium h-full text-white bg-blue-700 rounded-e-lg border border-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
            >
              <svg
                class="w-4 h-4"
                aria-hidden="true"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 20 20"
              >
                <path
                  stroke="currentColor"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="m19 19-4-4m0-7A7 7 0 1 1 1 8a7 7 0 0 1 14 0Z"
                />
              </svg>
              <span class="sr-only">Search</span>
            </button>
          </div>
        </div>
      </.form>
    </div>
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

defmodule SanbaseWeb.LiveSearch do
  use SanbaseWeb, :live_view
  import SanbaseWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative" x-data="{ showIcon: true }">
      <.input
        name="search"
        value={@query}
        phx-keyup="do-search"
        phx-debounce="200"
        class="pl-20"
        {
          [
            {"x-on:focus", "showIcon = false"},
            {"x-on:keyup", "showIcon = false"},
            {"x-on:blur", "showIcon = true"}
          ]
        }
      />
      <span class="absolute left-2 top-1/2 transform -translate-y-1/2" x-show="showIcon">
        <.icon name="hero-magnifying-glass" class="h-6 w-6 text-gray-500" />
      </span>
    </div>
    <.results routes={@routes} />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:routes, [])
     |> assign(:show_icon, true), layout: false}
  end

  @impl true
  def handle_event("do-search", %{"value" => query}, socket) do
    query = String.downcase(query)
    {:noreply, assign(socket, routes: search_routes(query), query: String.downcase(query))}
  end

  def results(assigns) do
    ~H"""
    <ul>
      <%= for {name, path} <- @routes do %>
        <li>
          <.link href={path} style="color: white;"><%= name %></.link>
        </li>
      <% end %>
    </ul>
    """
  end

  def search_routes("") do
    []
  end

  def search_routes(query) do
    SanbaseWeb.GenericController.all_routes()
    |> Enum.map(fn {name, _path} = tuple ->
      name = String.downcase(name)
      query = String.downcase(query)

      similarity = FuzzyCompare.similarity(query, name)
      {tuple, similarity}
    end)
    |> Enum.filter(fn {_, similarity} -> similarity > 0.9 end)
    |> Enum.sort_by(fn {_, similarity} -> similarity end, :desc)
    |> Enum.map(fn {result, _similarity} -> result end)
  end
end

defmodule SanbaseWeb.LiveSelect do
  use SanbaseWeb, :live_view
  use Phoenix.HTML

  import SanbaseWeb.CoreComponents
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.input
        type="text"
        label={humanize(@session["field"])}
        name={@session["parent_resource"] <> "[" <> to_string(@session["field"]) <> "_id" <> "]"}
        value={@query || @session["initial_value"]}
        list={"matches_" <> to_string(@session["field"])}
        phx-keyup="suggest"
        phx-debounce="200"
        placeholder="Search..."
      />
      <datalist id={"matches_" <> to_string(@session["field"])}>
        <%= for {id, match} <- @matches do %>
          <option value={id}><%= match %></option>
        <% end %>
      </datalist>
    </div>
    """
  end

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       query: nil,
       result: nil,
       loading: false,
       matches: [],
       session:
         Map.take(session, [
           "resource",
           "search_fields",
           "field",
           "parent_resource",
           "initial_value"
         ])
     ), layout: false}
  end

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) < 2 do
    session = socket.assigns[:session]

    Integer.parse(query)
    |> case do
      {id, ""} -> {:noreply, assign(socket, matches: search_matches_by_id(id, session))}
      _ -> {:noreply, assign(socket, matches: [])}
    end
  end

  def handle_event("suggest", %{"value" => query}, socket)
      when byte_size(query) >= 2 and byte_size(query) <= 100 do
    session = socket.assigns[:session]

    Integer.parse(query)
    |> case do
      {id, ""} -> {:noreply, assign(socket, matches: search_matches_by_id(id, session))}
      _ -> {:noreply, assign(socket, matches: search_matches(query, session))}
    end
  end

  def search_matches_by_id(id, session) do
    resource = session["resource"]
    search_fields = session["search_fields"]
    resource_module_map = SanbaseWeb.GenericAdmin.resource_module_map()
    module = resource_module_map[resource][:module]

    full_match_query =
      from(m in module, where: m.id == ^id, select_merge: %{})
      |> select_merge([p], map(p, [:id]))
      |> select_merge([p], map(p, ^search_fields))

    full_matches = Sanbase.Repo.all(full_match_query)

    format_results(full_matches, [])
  end

  def search_matches(query, session) do
    resource = session["resource"]
    search_fields = session["search_fields"]
    resource_module_map = SanbaseWeb.GenericAdmin.resource_module_map()
    module = resource_module_map[resource][:module]
    value = "%" <> query <> "%"

    base_query = from(m in module, select_merge: %{})

    full_match_query = build_full_match_query(search_fields, base_query, query)
    partial_match_query = build_partial_match_query(search_fields, base_query, value)

    full_matches = Sanbase.Repo.all(full_match_query)
    partial_matches = Sanbase.Repo.all(partial_match_query)

    format_results(full_matches, partial_matches)
  end

  defp build_full_match_query(search_fields, base_query, value) do
    Enum.reduce(search_fields, base_query, fn field, acc ->
      or_where(acc, [p], field(p, ^field) == ^value)
    end)
    |> select_merge([p], map(p, [:id]))
    |> select_merge([p], map(p, ^search_fields))
    |> order_by([p], desc: p.id)
  end

  defp build_partial_match_query(search_fields, base_query, value) do
    Enum.reduce(search_fields, base_query, fn field, acc ->
      or_where(acc, [p], ilike(field(p, ^field), ^value))
    end)
    |> select_merge([p], map(p, [:id]))
    |> select_merge([p], map(p, ^search_fields))
    |> order_by([p], desc: p.id)
  end

  defp format_results(full_matches, partial_matches) do
    (full_matches ++ partial_matches)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(10)
    |> Enum.map(fn result ->
      formatted = Enum.map(result, fn {key, value} -> "#{key}: #{value}" end) |> Enum.join(", ")
      {result.id, formatted}
    end)
  end
end
