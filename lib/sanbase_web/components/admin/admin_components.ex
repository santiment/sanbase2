defmodule SanbaseWeb.AdminComponents do
  use Phoenix.Component, global_prefixes: ~w(x-)

  use PhoenixHTMLHelpers

  import SanbaseWeb.CoreComponents

  alias SanbaseWeb.Router.Helpers, as: Routes

  @doc """
  Renders a bottom navigation for a form.

  ## Attributes

  - `:resource` - The resource that the form is for.
  - `:type` - The type of the form, either "new" or "edit".

  ## Example

  <.form_nav
    resource="users"
    type="new"
  />
  """

  attr(:resource, :string, required: true)
  attr(:type, :string, required: true)

  def form_bottom_nav(assigns) do
    ~H"""
    <div class="flex justify-end">
      <.action_btn resource={@resource} action={:index} label="Back" color={:white} />
      <.btn label={if @type == "new", do: "Create", else: "Update"} href="#" type="submit" />
    </div>
    """
  end

  @doc """
  Renders an error message for a form.

  ## Attributes

  - `:changeset` - The changeset containing the form errors.

  ## Example

  <.form_error
    changeset={@changeset}
  />
  """

  attr(:changeset, :map, required: true)

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

  @doc """
  Renders an input field for a form.

  ## Attributes

  - `:resource` - The resource that the form is for.
  - `:field` - The field name for the input.
  - `:field_type_map` - A map of field types for the form fields.
  - `:type` - The type of the form, either "new" or "edit".
  - `:changeset` - The changeset containing the form data.
  - `:data` - Additional data for the form.

  ## Example


  <.form_input
    resource="users"
    field={:name}
    field_type_map={%{name: :text}}
    type="new"
    changeset={@changeset}
    data=%{}
  />
  """

  attr(:resource, :string, required: true)
  attr(:field, :atom, required: true)
  attr(:field_type_map, :map, required: true)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :map, required: false, default: %{})

  def form_input(assigns) do
    # If this is a form for creating a new entity, value is empty
    # Otherwise it is taken from the changeset or data fields
    value =
      if assigns.type == "new" do
        ""
      else
        case Map.get(assigns.field_type_map, assigns.field) do
          map_or_list when map_or_list in [:map, :list] ->
            Map.get(assigns.changeset.data, assigns.field) |> Jason.encode!()

          _ ->
            Map.get(assigns.changeset.changes, assigns.field) ||
              Map.get(assigns.changeset.data, assigns.field) ||
              Map.get(assigns.data, assigns.field)
        end
      end

    # type of the <input> html tag
    type =
      case Map.get(assigns.field_type_map, assigns.field) do
        :string -> "text"
        :text -> "textarea"
        :integer -> "number"
        :float -> "number"
        :boolean -> "checkbox"
        :date -> "date"
        :naive_datetime -> "datetime-local"
        :utc_datetime -> "datetime-local"
        :time -> "time"
        :map -> "text"
        :list -> "text"
        :assoc -> "text"
        :binary -> "text"
        :any -> "text"
        _ -> "text"
      end

    assigns =
      assign(assigns,
        value: value,
        type: type
      )

    ~H"""
    <.input
      name={@resource <> "[" <> to_string(@field) <> "]"}
      id={@resource <> "_" <> to_string(@field)}
      label={humanize(@field)}
      type={@type}
      value={@value}
    />
    """
  end

  @doc """
  Renders a select field for a form.

  ## Attributes

  - `:resource` - The resource that the form is for.
  - `:field` - The field name for the select input.
  - `:options` - The options for the select input.
  - `:select_type` - The type of the select input, either `:select` or `:multiselect`.
  - `:belongs_to` - Whether the field belongs to another resource.
  - `:type` - The type of the form, either "new" or "edit".
  - `:changeset` - The changeset containing the form data.

  ## Example

  <.form_select
    resource="users"
    field={:role}
    options={[{1, "admin"}, {2, "user"}]}
    select_type=:select
    belongs_to=false
    type="new"
    changeset={@changeset}
  />
  """

  attr(:resource, :string, required: true)
  attr(:field, :atom, required: true)
  attr(:options, :list, required: true)
  attr(:select_type, :atom, required: false, default: :select)
  attr(:belongs_to, :boolean, required: false, default: false)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)

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

  @doc """
  Renders a table for displaying a resource.

  ## Attributes

  - `:resource` - The resource that the table is for.
  - `:fields` - The fields to be displayed in the table.
  - `:assocs` - The associations for the resource.
  - `:data` - The data for the resource.
  - `:funcs` - The functions to be applied to the data.
  - `:field_type_map` - A map of field types for the table fields.

  ## Example

  <.show_table
    resource="users"
    fields={[:name, :email]}
    assocs={%{}}
    data={@user}
    funcs={%{}}
    field_type_map={%{name: :text}}
  />
  """

  attr(:resource, :string, required: true)
  attr(:fields, :list, required: true)
  attr(:assocs, :map, required: false, default: %{})
  attr(:data, :map, required: true)
  attr(:funcs, :map, required: false, default: %{})
  attr(:field_type_map, :map, required: true)

  def show_table(assigns) do
    ~H"""
    <div class="mt-4">
      <h3 class="text-2xl font-medium text-gray-700 mb-2">
        Show <%= Inflex.singularize(@resource) %>
      </h3>
      <div class="relative shadow-md sm:rounded-lg">
        <div class="overflow-x-auto">
          <table class="w-full text-xs text-left rtl:text-right text-gray-500 dark:text-gray-400 min-w-full table-fixed">
            <tbody>
              <%= for field <- @fields do %>
                <tr class="hover:bg-gray-50 dark:hover:bg-gray-600">
                  <th class="text-xs px-2 py-1 text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400 border-b border-gray-200 whitespace-nowrap w-1/4">
                    <%= to_string(field) %>
                  </th>
                  <.td_show
                    class="px-3 py-2 border-b border-gray-200 whitespace-pre-wrap break-words"
                    value={
                      result =
                        if @assocs[@data.id][field],
                          do: @assocs[@data.id][field],
                          else: Map.get(@data, field)

                      result =
                        if @funcs[field] != nil, do: @funcs[field].(@data), else: result

                      case Map.get(@field_type_map, field) do
                        :map ->
                          if is_binary(result), do: result, else: Jason.encode!(result)

                        :list ->
                          if is_binary(result), do: result, else: Jason.encode!(result)

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

  @doc """
  Renders a table for displaying a resource that has many associations.

  ## Attributes

  - `:resource` - The resource that the table is for.
  - `:resource_name` - The name of the resource.
  - `:create_link_kv` - The link for creating a new resource with prefilled data.
  - `:fields` - The fields to be displayed in the table.
  - `:rows` - The rows of data for the table.
  - `:funcs` - The functions to be applied to the data.

  ## Example

  ```elixir
  <.has_many_table
    resource="users"
    resource_name="Users"
    create_link_kv={[]}
    fields={[:name, :email]}
    rows={@users}
    funcs={%{}}
  />
  """

  attr(:resource, :string, required: true)
  attr(:resource_name, :string, required: true)
  attr(:create_link_kv, :list, required: false, default: [])
  attr(:fields, :list, required: true)
  attr(:rows, :list, required: true)
  attr(:funcs, :map, required: false, default: %{})

  def has_many_table(assigns) do
    ~H"""
    <div class="table-responsive">
      <div class="m-4 flex flex-col gap-x-10">
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

  @doc """
  Renders a index table for displaying a resource.

  ## Attributes
  - `:resource` - The resource that the table is for.
  - `:fields` - The fields to be displayed in the table.
  - `:rows` - The rows of data for the table.
  - `:assocs` - The associations for the resource.
  - `:field_type_map` - A map of field types for the table fields.
  - `:actions` - The actions to be displayed in the table.
  - `:funcs` - The functions to be applied to the data.
  - `:search_fields` - The fields to be searched in the table.
  - `:search` - The search data for the table.
  - `:rows_count` - The total number of rows for the table.
  - `:page_size` - The page size for the table.
  - `:current_page` - The current page for the table.
  - `:action` - The action for the table.

  ## Example
  ```elixir

  <.table
    resource="users"
    fields={[:name, :email]}
    rows={@users}
    assocs={%{}}
    field_type_map={%{}}
    actions=[:show, :edit, :delete]
    funcs={%{}}
    search_fields=[:name, :email]
    search=%{}
    rows_count=10
    page_size=10
    current_page=1
  />
  ```
  """

  attr(:resource, :string, required: true)
  attr(:fields, :list, required: true)
  attr(:rows, :list, required: true)
  attr(:assocs, :map, required: false, default: %{})
  attr(:field_type_map, :map, required: false, default: %{})
  attr(:actions, :list, required: false, default: [])
  attr(:funcs, :map, required: false, default: %{})
  attr(:search_fields, :list, required: false, default: [])
  attr(:search, :map, required: false, default: %{})
  attr(:rows_count, :integer, required: false, default: 0)
  attr(:page_size, :integer, required: false, default: 0)
  attr(:current_page, :integer, required: false, default: 1)
  attr(:action, :atom, required: false, default: :index)

  def table(assigns) do
    ~H"""
    <div class="table-responsive">
      <div class="m-4 flex flex-col md:flex-row md:items-center gap-y-2 md:gap-x-10">
        <%= if :new in @actions do %>
          <.new_resource_button resource={@resource} />
        <% end %>
        <.search fields={@search_fields} resource={@resource} search={@search} />
      </div>
      <div class="relative shadow-md sm:rounded-lg">
        <div class="overflow-x-auto pr-4" style="max-height: calc(85vh - 180px);">
          <table class="w-full text-xs text-left rtl:text-right text-gray-500 dark:text-gray-400 min-w-full table-fixed">
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

        <.pagination
          resource={@resource}
          rows_count={@rows_count}
          page_size={@page_size}
          current_page={@current_page}
          action={@action}
          search={@search}
        />
      </div>
    </div>
    """
  end

  def thead(assigns) do
    ~H"""
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400 sticky top-0">
      <tr>
        <%= for field <- @fields do %>
          <th scope="col" class="px-2 py-1 whitespace-nowrap min-w-[120px]"><%= field %></th>
        <% end %>
        <%= if @actions do %>
          <th scope="col" class="px-2 py-1 whitespace-nowrap w-[140px] min-w-[140px]">Actions</th>
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
              <td class="px-3 py-2 min-w-[120px]">
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
            <td class="px-3 py-2 w-[140px] min-w-[140px]">
              <div class="flex flex-row flex-nowrap gap-1 items-center">
                <% index_actions = @actions -- [:new] %>
                <%= for action <- index_actions do %>
                  <.index_action_btn resource={@resource} action={action} label={action} row={row} />
                <% end %>
              </div>
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

  @doc """
  Renders a button for creating a new resource.

  ## Attributes
  - `:resource` - The resource that the button is for.
  - `:create_link_kv` - The key-value pairs for creating a new resource with prefilled data.

  ## Example
  ```elixir
  <.new_resource_button resource="users" create_link_kv={[linked_resource: :project, linked_resource_id: 100]} />
  ```
  """

  attr(:resource, :string, required: true)
  attr(:create_link_kv, :list, required: false, default: [])

  def new_resource_button(assigns) do
    ~H"""
    <button
      type="button"
      class="text-white w-fit p-2 bg-blue-500 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
    >
      <.link href={
        Routes.generic_admin_path(
          SanbaseWeb.Endpoint,
          :new,
          Keyword.merge([resource: @resource], @create_link_kv)
        )
      }>
        <.icon name="hero-plus-circle" /> Add new <%= Inflex.singularize(@resource) %>
      </.link>
    </button>
    """
  end

  @doc """
  Action button for the index table.

  ## Attributes
  - `:resource` - The resource that the button is for.
  - `:action` - The action for the button. One of :edit, :show, :delete
  - `:row` - The record in the row in the table.
  - `:label` - The label for the button.

  ## Example
  ```elixir
  <.index_action_btn resource="users" action={:edit} row={@user} label="Edit" />
  ```
  """

  attr(:resource, :string, required: true)
  attr(:action, :atom, required: true)
  attr(:row, :map, required: true)
  attr(:label, :string, required: true)

  def index_action_btn(%{action: :delete} = assigns) do
    ~H"""
    <.form
      for={%{}}
      action={Routes.generic_admin_path(SanbaseWeb.Endpoint, @action, @row, resource: @resource)}
      method="post"
      class="inline"
      data-confirm="Are you sure you want to delete this?"
    >
      <input type="hidden" name="_method" value="delete" />
      <.btn color={:red} size={:small} type="submit" href="#" label={@label} />
    </.form>
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
      href={Routes.generic_admin_path(SanbaseWeb.Endpoint, @action, @row, resource: @resource)}
      label={@label}
    />
    """
  end

  def back_btn(assigns) do
    ~H"""
    <.btn href={{:javascript, "javascript:history.back()"}} label="Back" color={:white} />
    """
  end

  attr(:resource, :string, required: true)
  attr(:action, :atom, required: true)
  attr(:label, :string, required: true)
  attr(:color, :atom, required: true)

  def action_btn(assigns) do
    ~H"""
    <.btn
      href={Routes.generic_admin_path(SanbaseWeb.Endpoint, @action, resource: @resource)}
      label={@label}
      color={@color}
    />
    """
  end

  attr(:value, :string, required: true)

  def td_index(assigns) do
    ~H"""
    <td class="px-3 py-2 whitespace-nowrap overflow-hidden text-ellipsis min-w-[120px]">
      <%= @value %>
    </td>
    """
  end

  attr(:value, :string, required: true)
  attr(:class, :string, required: false, default: "")

  def td_show(assigns) do
    ~H"""
    <td class={@class}>
      <%= @value %>
    </td>
    """
  end

  attr(:resource, :string, required: true)
  attr(:action, :atom, required: true)
  attr(:row, :map, required: true)
  attr(:label, :string, required: true)

  def a(assigns) do
    ~H"""
    <.link
      href={Routes.generic_admin_path(SanbaseWeb.Endpoint, @action, @row, resource: @resource)}
      class="underline"
    >
      <%= @label %>
    </.link>
    """
  end

  @doc """
  Renders a pagination component.

  ## Attributes
  - `:resource` - The resource that the pagination is for.
  - `:rows_count` - The total number of rows for the table.
  - `:page_size` - The page size for the table.
  - `:current_page` - The current page for the table.
  - `:action` - The action - :index or :search.
  - `:search` - The search data for the table. Ex: %{"field" => "ticker", "value" => "SAN"}

  ## Example
  ```elixir
  <.pagination
    resource="users"
    rows_count=10
    page_size=10
    current_page=1
    action=:index
    search={%{"field" => "ticker", "value" => "SAN"}}
  />
  ```
  """

  attr(:resource, :string, required: true)
  attr(:rows_count, :integer, required: true)
  attr(:page_size, :integer, required: true)
  attr(:current_page, :integer, required: true)
  attr(:action, :atom, required: true)
  attr(:search, :map, required: false, default: %{})

  def pagination(assigns) do
    ~H"""
    <div class="flex justify-between items-center p-2 text-xs border-t">
      <.pagination_buttons
        resource={@resource}
        rows_count={@rows_count}
        page_size={@page_size}
        current_page={@current_page}
        action={@action}
        search={@search}
      />
      <span class="text-xs text-gray-700">
        Showing <%= @current_page * @page_size + 1 %> to <%= Enum.min([
          (@current_page + 1) * @page_size,
          @rows_count
        ]) %> of <%= @rows_count %> entries
      </span>
    </div>
    """
  end

  attr(:resource, :string, required: true)
  attr(:action, :atom, required: true)
  attr(:search, :map, required: true)
  attr(:current_page, :integer, required: true)
  attr(:rows_count, :integer, required: true)
  attr(:page_size, :integer, required: true)

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
        Routes.generic_admin_path(SanbaseWeb.Endpoint, action, %{
          resource: resource,
          page: page_number
        })

      :search ->
        Routes.generic_admin_path(SanbaseWeb.Endpoint, action, %{
          "resource" => resource,
          "page" => page_number,
          "search" => search
        })
    end
  end

  @doc """
  # The component was borrowed from: https://flowbite.com/docs/forms/search-input/#search-with-dropdown

  Renders a search component with a dropdown for selecting the search field.

  ## Attributes
  - `:fields` - The fields to be displayed in the dropdown.
  - `:resource` - The resource that the search is for.
  - `:search` - The search data for the table.

  ## Example
  ```elixir
  <.search resource="users" fields={[:name, :email]} />
  ```
  """

  attr(:resource, :string, required: true)
  attr(:fields, :list, required: true)
  attr(:search, :map, required: false, default: %{})

  def search(assigns) do
    ~H"""
    <div x-data={
      Jason.encode!(%{
        open: false,
        filters: Map.get(assigns.search || %{}, "filters") || [%{"field" => "Fields", "value" => ""}],
        showError: false
      })
    }>
      <div class="flex flex-col gap-2">
        <.form
          for={%{}}
          as={:search}
          method="get"
          action={Routes.generic_admin_path(SanbaseWeb.Endpoint, :search, resource: @resource)}
          class="max-w-lg md:w-96"
          x-on:submit.prevent="if (filters.some(f => f.field === 'Fields')) { showError = true; return false; } $el.submit();"
        >
          <input type="hidden" name="resource" value={@resource} />

          <div x-bind:id="'filters-container'">
            <template x-for="(filter, index) in filters">
              <div class="flex flex-col gap-2 mb-4">
                <div class="flex">
                  <div class="relative">
                    <button
                      @click="open = index; showError = false"
                      type="button"
                      class="flex-shrink-0 z-10 inline-flex items-center py-2.5 px-4 text-sm font-medium text-center text-gray-900 bg-gray-100 border border-gray-300 rounded-s-lg hover:bg-gray-200 focus:ring-4 focus:outline-none focus:ring-gray-100 dark:bg-gray-700 dark:hover:bg-gray-600 dark:focus:ring-gray-700 dark:text-white dark:border-gray-600"
                      x-bind:class="{'border-red-500': showError && filter.field === 'Fields'}"
                    >
                      <div class="flex items-center">
                        <span x-text="filter.field"></span>
                        <.icon name="hero-chevron-down" class="w-2.5 h-2.5 ms-2.5" />
                      </div>
                    </button>

                    <div
                      x-show="open === index"
                      @click.away="open = false"
                      class="mt-12 absolute z-20 bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700"
                    >
                      <ul class="py-2 text-sm text-gray-700 dark:text-gray-200">
                        <%= for field <- @fields do %>
                          <li>
                            <button
                              @click="filter.field = $event.target.innerText; open = false; showError = false"
                              type="button"
                              class="inline-flex w-full px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                            >
                              <%= field %>
                            </button>
                          </li>
                        <% end %>
                      </ul>
                    </div>
                  </div>

                  <div class="relative w-full">
                    <input
                      x-bind:name="`search[filters][${index}][field]`"
                      type="hidden"
                      x-bind:value="filter.field"
                    />
                    <input
                      x-bind:name="`search[filters][${index}][value]`"
                      type="search"
                      class="block p-2.5 w-full z-20 text-sm text-gray-900 bg-gray-50 rounded-e-lg border-s-gray-50 border-s-2 border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-s-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:border-blue-500"
                      placeholder="Search..."
                      required
                      x-model="filter.value"
                    />
                  </div>

                  <button
                    type="button"
                    class="ml-2 text-red-600 hover:text-red-800"
                    @click="filters = filters.filter((_, i) => i !== index)"
                    x-show="filters.length > 1"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>
            </template>
          </div>

          <div class="flex justify-between items-center">
            <button
              type="button"
              @click="filters.push({field: 'Fields', value: ''})"
              class="text-sm text-blue-600 hover:text-blue-800"
            >
              <div class="flex items-center">
                <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add filter
              </div>
            </button>

            <button
              type="submit"
              class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-4 py-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
            >
              <div class="flex items-center">
                <.icon name="hero-magnifying-glass" class="w-4 h-4 mr-2" /> Search
              </div>
            </button>
          </div>

          <div x-show="showError" x-cloak class="text-red-500 text-sm mt-1">
            Please select a field for all filters
          </div>
        </.form>

        <%= if @search["filters"] do %>
          <.link
            href={Routes.generic_admin_path(SanbaseWeb.Endpoint, :index, resource: @resource)}
            class="inline-flex items-center px-4 py-2 text-sm font-medium text-gray-900 bg-white border border-gray-200 rounded-lg hover:bg-gray-100 hover:text-blue-700 focus:z-10 focus:ring-4 focus:outline-none focus:ring-gray-100 dark:bg-gray-800 dark:text-gray-400 dark:border-gray-600 dark:hover:text-white dark:hover:bg-gray-700 dark:focus:ring-gray-700"
          >
            <.icon name="hero-x-mark" class="w-4 h-4 mr-2" /> Reset Filters
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a resource title.

  ## Attributes

    - `:resource` - The name of the resource.

  ## Example

      <.resource_title resource="users" />
  """
  attr(:resource, :string, required: true)

  def resource_title(assigns) do
    ~H"""
    <h1 class="text-3xl font-bold mb-6">
      <%= Inflex.camelize(@resource) %>
    </h1>
    """
  end
end
