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
      <.action_btn resource={@resource} action={:index} label="Back" color={:white} />
      <.btn label={if @type == "new", do: "Create", else: "Update"} href="#" type="submit" />
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
        name =
          if @belongs_to do
            @resource <> "[" <> to_string(@field) <> "_id" <> "]"
          else
            @resource <> "[" <> to_string(@field) <> "]"
          end

        if @select_type == :multiselect, do: name <> "[]", else: name
      }
      id={@resource <> "_" <> to_string(@field)}
      label={humanize(@field)}
      type="select"
      multiple={if @select_type == :multiselect, do: true, else: false}
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

  def show_table(assigns) do
    ~H"""
    <div class="mt-6">
      <h3 class="text-3xl font-medium text-gray-700">Show <%= Inflex.singularize(@resource) %></h3>
      <div class="table-responsive">
        <div class="relative overflow-x-auto shadow-md sm:rounded-lg">
          <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
            <tbody>
              <%= for field <- @fields do %>
                <tr class="hover:bg-gray-50 dark:hover:bg-gray-600">
                  <th class="text-xs pl-2 text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400 border-b border-gray-200">
                    <%= to_string(field) %>
                  </th>
                  <.td_show
                    class="px-6 py-4 border-b border-gray-200"
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
    </div>
    """
  end

  def has_many_table(assigns) do
    ~H"""
    <div class="table-responsive">
      <div class="m-4">
        <h3 class="text-3xl font-medium text-gray-700 mb-2"><%= @resource_name %></h3>
        <%= if @create_link_kv != [] do %>
          <.new_resource_button resource={@resource} create_link_kv={@create_link_kv} />
        <% end %>
      </div>
      <div class="relative overflow-x-auto shadow-md sm:rounded-lg">
        <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
          <.thead fields={@fields} actions={[]} />
          <.tbody
            resource={@resource}
            rows={@rows}
            fields={@fields}
            assocs={%{}}
            field_type_map={%{}}
            actions={[]}
            funcs={@funcs}
          />
        </table>
      </div>
    </div>
    """
  end

  def table(assigns) do
    ~H"""
    <div class="table-responsive">
      <div class="ml-4">
        <.search fields={@search_fields} resource={@resource} search={@search} />
        <%= if :new in @actions do %>
          <.new_resource_button resource={@resource} create_link_kv={[]} />
        <% end %>
      </div>
      <div class="relative overflow-x-auto shadow-md sm:rounded-lg">
        <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
          <.thead fields={@fields} actions={@actions} />
          <.tbody
            resource={@resource}
            rows={@rows}
            fields={@fields}
            assocs={@assocs}
            field_type_map={@field_type_map}
            actions={@actions}
            funcs={@funcs}
          />
        </table>
      </div>
    </div>
    """
  end

  def thead(assigns) do
    ~H"""
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <%= for field <- @fields do %>
          <th scope="col" class="px-6 py-3"><%= field %></th>
        <% end %>
        <%= if @actions do %>
          <th scope="col" class="px-6 py-3">Actions</th>
        <% end %>
      </tr>
    </thead>
    """
  end

  def tbody(assigns) do
    ~H"""
    <tbody>
      <%= for row <- @rows do %>
        <tr class="bg-white border-b dark:bg-gray-800 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600">
          <%= for field <- @fields do %>
            <%= if field == :id do %>
              <td class="px-6 py-4">
                <.a resource={@resource} action={:show} row={row} label={Map.get(row, field)} />
              </td>
            <% else %>
              <.td_index value={
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
          <%= if @actions do %>
            <td class="px-6 py-4">
              <% index_actions = @actions -- [:new] %>
              <%= for action <- index_actions do %>
                <.index_action_btn resource={@resource} action={action} label={action} row={row} />
              <% end %>
            </td>
          <% end %>
        </tr>
      <% end %>
    </tbody>
    """
  end

  attr(:color, :atom, required: false, default: :blue)
  attr(:size, :atom, required: false, default: :normal)
  attr(:href, :string, required: true)
  attr(:label, :string, required: true)
  attr(:type, :string, required: false, default: "button")

  def btn(assigns) do
    ~H"""
    <.link href={@href}>
      <button
        type={@type}
        class={
          classes = %{
            blue: %{
              small:
                "text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-xs px-4 py-2 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800",
              normal:
                "text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
            },
            yellow: %{
              small:
                "focus:outline-none text-white bg-yellow-400 hover:bg-yellow-500 focus:ring-4 focus:ring-yellow-300 font-medium rounded-lg text-xs px-4 py-2 me-2 mb-2 dark:focus:ring-yellow-900",
              normal:
                "focus:outline-none text-white bg-yellow-400 hover:bg-yellow-500 focus:ring-4 focus:ring-yellow-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:focus:ring-yellow-900"
            },
            red: %{
              small:
                "focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-xs px-4 py-2 me-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900",
              normal:
                "focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900"
            },
            white: %{
              normal:
                "py-2.5 px-5 me-2 mb-2 text-sm font-medium text-gray-900 focus:outline-none bg-white rounded-lg border border-gray-200 hover:bg-gray-100 hover:text-blue-700 focus:z-10 focus:ring-4 focus:ring-gray-100 dark:focus:ring-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:border-gray-600 dark:hover:text-white dark:hover:bg-gray-700"
            }
          }

          classes[@color][@size]
        }
      >
        <%= @label %>
      </button>
    </.link>
    """
  end

  def new_resource_button(assigns) do
    ~H"""
    <button
      type="button"
      class="text-white bg-blue-500 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
    >
      <.link href={
        if @create_link_kv,
          do:
            Routes.generic_path(
              SanbaseWeb.Endpoint,
              :new,
              Keyword.merge([resource: @resource], @create_link_kv)
            ),
          else: Routes.generic_path(SanbaseWeb.Endpoint, :new, resource: @resource)
      }>
        <.icon name="hero-plus-circle" /> Add new <%= Inflex.singularize(@resource) %>
      </.link>
    </button>
    """
  end

  def index_action_btn(assigns) do
    ~H"""
    <.btn
      color={
        case @action do
          :edit -> :yellow
          :show -> :blue
          :delete -> :red
        end
      }
      size={:small}
      href={Routes.generic_path(SanbaseWeb.Endpoint, @action, @row, resource: @resource)}
      label={@label}
    />
    """
  end

  def back_btn(assigns) do
    ~H"""
    <.btn href={{:javascript, "javascript:history.back()"}} label="Back" color={:white} />
    """
  end

  def action_btn(assigns) do
    ~H"""
    <.btn
      href={Routes.generic_path(SanbaseWeb.Endpoint, @action, resource: @resource)}
      label={@label}
      color={@color}
    />
    """
  end

  def link_btn(assigns) do
    ~H"""
    <.btn href={@href} label={@text} color={:blue} />
    """
  end

  def td_index(assigns) do
    ~H"""
    <td class="px-6 py-4">
      <%= @value %>
    </td>
    """
  end

  def td_show(assigns) do
    ~H"""
    <td class={@class}>
      <%= @value %>
    </td>
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

  # The component was borrowed from: https://flowbite.com/docs/forms/search-input/#search-with-dropdown
  def search(assigns) do
    ~H"""
    <div
      class="mb-4"
      x-data={Jason.encode!(%{open: false, selectedField: @search["field"] || "Fields"})}
    >
      <.form
        for={%{}}
        as={:search}
        method="get"
        action={Routes.generic_path(SanbaseWeb.Endpoint, :search, resource: @resource)}
        class="max-w-lg mx-auto mt-2"
      >
        <input type="hidden" name="search[field]" x-bind:value="selectedField" />
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
              <.icon name="hero-chevron-down" class="w-2.5 h-2.5 ms-2.5" />
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
              name="search[value]"
              type="search"
              id="search-dropdown"
              class="block p-2.5 w-full z-20 text-sm text-gray-900 bg-gray-50 rounded-e-lg border-s-gray-50 border-s-2 border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-s-gray-700  dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:border-blue-500"
              placeholder="Search ..."
              required
              value={@search["value"] || ""}
            />
            <button
              type="submit"
              class="absolute top-0 end-0 p-2.5 text-sm font-medium h-full text-white bg-blue-700 rounded-e-lg border border-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
            >
              <.icon name="hero-magnifying-glass" class="w-4 h-4" />
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
        search={@search}
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
          href={pagination_path(@resource, @action, @search, @current_page - 1)}
          class="px-4 py-2 mx-1 bg-gray-200 rounded hover:bg-gray-300"
        >
          Previous
        </.link>
      <% end %>
      <%= unless @current_page >= div(@rows_count - 1, @page_size) do %>
        <.link
          href={pagination_path(@resource, @action, @search, @current_page + 1)}
          class="px-4 py-2 mx-1 bg-gray-200 rounded hover:bg-gray-300"
        >
          Next
        </.link>
      <% end %>
    </div>
    """
  end

  defp pagination_path(resource, action, search, page_number) do
    case action do
      :index ->
        Routes.generic_path(SanbaseWeb.Endpoint, action, %{resource: resource, page: page_number})

      :search ->
        Routes.generic_path(SanbaseWeb.Endpoint, action, %{
          "resource" => resource,
          "page" => page_number,
          "search" => search
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
    <div
      x-data="{results_open: true}"
      @click="results_open = true"
      @click.outside="results_open = false"
    >
      <div class="relative m-3">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" />
        </div>
        <input
          value={@query}
          phx-keyup="do-search"
          phx-debounce="200"
          type="text"
          id="simple-search"
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full ps-10 p-2.5  dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          placeholder="Search resources..."
          required
        />
      </div>
      <ul
        x-show="results_open"
        x-transition
        class="absolute ml-2 py-2 text-gray-700 dark:text-gray-200 border shadow-xl bg-blue-50 rounded-xl"
        aria-labelledby="dropdownDefaultButton"
      >
        <li :for={{name, path} <- @routes}>
          <a
            href={path}
            class="block p-4 hover:bg-blue-100 dark:hover:bg-gray-600 dark:hover:text-white text-md font-semibold"
          >
            <%= name %>
          </a>
        </li>
      </ul>
    </div>
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
