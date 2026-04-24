defmodule SanbaseWeb.AdminComponents do
  @moduledoc """
  Phoenix function components for the GenericAdmin CRUD interface.

  Provides the full set of UI building blocks used by GenericAdmin templates:

  - **Form components** — `form_input`, `form_select`, `form_error`, `form_bottom_nav`
  - **Table components** — `table` (index), `show_table` (detail), `has_many_table`,
    `thead`, `tbody`, `td_index`, `td_show`
  - **Navigation** — `btn`, `new_resource_button`, `index_action_btn`, `back_btn`,
    `action_btn`, `a`, `pagination`, `pagination_buttons`
  - **Search** — `search` (multi-filter search with AlpineJS dropdown)
  - **Display** — `resource_title`, `custom_index_actions`

  These components are used in the HEEx templates under
  `lib/sanbase_web/templates/generic_admin_html/`.
  """
  use Phoenix.Component, global_prefixes: ~w(x-)

  use PhoenixHTMLHelpers
  use SanbaseWeb, :verified_routes

  import SanbaseWeb.CoreComponents

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
            {humanize(attr)}: {Enum.join(message, ", ")}
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
    assigns =
      assign(assigns,
        value: resolve_input_value(assigns),
        type: input_html_type(Map.get(assigns.field_type_map, assigns.field))
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

  defp resolve_input_value(%{type: "new"}), do: ""

  defp resolve_input_value(%{field: field, field_type_map: ftm, changeset: cs, data: data}) do
    case Map.get(ftm, field) do
      type when type in [:map, :list, {:array, :string}] ->
        case Map.get(cs.data, field) do
          nil -> ""
          value -> Jason.encode!(value)
        end

      _ ->
        lookup_field(field, cs.changes, cs.data, data)
    end
  end

  defp lookup_field(field, changes, data, extra_data) do
    cond do
      Map.has_key?(changes, field) -> Map.get(changes, field)
      Map.has_key?(data, field) -> Map.get(data, field)
      true -> Map.get(extra_data, field)
    end
  end

  defp input_html_type(:text), do: "textarea"
  defp input_html_type(:integer), do: "number"
  defp input_html_type(:float), do: "number"
  defp input_html_type(:boolean), do: "checkbox"
  defp input_html_type(:date), do: "date"
  defp input_html_type(:naive_datetime), do: "datetime-local"
  defp input_html_type(:utc_datetime), do: "datetime-local"
  defp input_html_type(:time), do: "time"
  defp input_html_type(_), do: "text"

  @doc """
  Renders the full resource form in the compact (horizontal) layout.

  Labels sit on the left, inputs on the right. On small screens (<= 768px)
  the layout collapses to vertical via CSS media query.
  """

  attr(:conn, :any, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :any, required: true)
  attr(:type, :string, required: true)
  attr(:resource, :string, required: true)
  attr(:fields, :list, required: true)
  attr(:field_type_map, :map, required: true)
  attr(:belongs_to_fields, :map, required: true)
  attr(:collections, :map, required: true)
  attr(:fields_override, :map, required: true)
  attr(:form_label_width, :string, required: true)
  attr(:form_input_max_width, :any, required: true)

  def resource_form_compact(assigns) do
    ~H"""
    <.resource_form_shell type={@type} resource={@resource} data={@data} changeset={@changeset}>
      <.compact_field
        :for={field <- @fields}
        conn={@conn}
        field={field}
        resource={@resource}
        type={@type}
        changeset={@changeset}
        data={@data}
        field_type_map={@field_type_map}
        belongs_to_fields={@belongs_to_fields}
        collections={@collections}
        fields_override={@fields_override}
        form_label_width={@form_label_width}
        form_input_max_width={@form_input_max_width}
      />
      <.form_row_compact label_width={@form_label_width} input_max_width={@form_input_max_width}>
        <.form_bottom_nav type={@type} resource={@resource} />
      </.form_row_compact>
    </.resource_form_shell>
    """
  end

  @doc """
  Renders the full resource form in the vertical (stacked) layout: labels
  above inputs, each field wrapped in its own block.
  """

  attr(:conn, :any, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :any, required: true)
  attr(:type, :string, required: true)
  attr(:resource, :string, required: true)
  attr(:fields, :list, required: true)
  attr(:field_type_map, :map, required: true)
  attr(:belongs_to_fields, :map, required: true)
  attr(:collections, :map, required: true)

  def resource_form_vertical(assigns) do
    ~H"""
    <.resource_form_shell type={@type} resource={@resource} data={@data} changeset={@changeset}>
      <.vertical_field
        :for={field <- @fields}
        conn={@conn}
        field={field}
        resource={@resource}
        type={@type}
        changeset={@changeset}
        data={@data}
        field_type_map={@field_type_map}
        belongs_to_fields={@belongs_to_fields}
        collections={@collections}
      />
      <.form_bottom_nav type={@type} resource={@resource} />
    </.resource_form_shell>
    """
  end

  attr(:type, :string, required: true)
  attr(:resource, :string, required: true)
  attr(:data, :any, required: true)
  attr(:changeset, :map, required: true)
  slot(:inner_block, required: true)

  defp resource_form_shell(assigns) do
    ~H"""
    <.form
      method={if @type == "new", do: "post", else: "patch"}
      for={@changeset}
      as={@resource}
      action={form_action(@type, @resource, @data)}
    >
      <.form_error :if={@changeset.action} changeset={@changeset} />
      {render_slot(@inner_block)}
    </.form>
    """
  end

  attr(:conn, :any, required: true)
  attr(:field, :atom, required: true)
  attr(:resource, :string, required: true)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :any, required: true)
  attr(:field_type_map, :map, required: true)
  attr(:belongs_to_fields, :map, required: true)
  attr(:collections, :map, required: true)
  attr(:fields_override, :map, required: true)
  attr(:form_label_width, :string, required: true)
  attr(:form_input_max_width, :any, required: true)

  defp compact_field(assigns) do
    field_override = Map.get(assigns.fields_override, assigns.field, %{})
    label_width = Map.get(field_override, :label_width, assigns.form_label_width)
    input_max_width = Map.get(field_override, :input_max_width, assigns.form_input_max_width)
    input_id = assigns.resource <> "_" <> to_string(assigns.field)

    assigns =
      assign(assigns,
        kind: field_kind(assigns),
        label_width: label_width,
        input_max_width: input_max_width,
        input_id: input_id
      )

    ~H"""
    <.form_row_compact
      label={humanize(@field)}
      for={@input_id}
      label_width={@label_width}
      input_max_width={@input_max_width}
    >
      <.live_select_embed
        :if={@kind == :live_select}
        conn={@conn}
        field={@field}
        resource={@resource}
        type={@type}
        changeset={@changeset}
        data={@data}
        belongs_to_fields={@belongs_to_fields}
        no_label={true}
      />
      <.form_select_compact
        :if={@kind == :belongs_to}
        type={@type}
        resource={@resource}
        field={@field}
        changeset={@changeset}
        data={@data}
        options={@belongs_to_fields[@field][:data]}
        belongs_to={true}
        select_type={@field_type_map[@field] || :select}
      />
      <.form_select_compact
        :if={@kind == :collection}
        type={@type}
        resource={@resource}
        field={@field}
        changeset={@changeset}
        data={@data}
        options={@collections[@field]}
        belongs_to={false}
        select_type={@field_type_map[@field] || :select}
      />
      <.form_input_compact
        :if={@kind == :input}
        type={@type}
        resource={@resource}
        field={@field}
        changeset={@changeset}
        field_type_map={@field_type_map}
        data={@data}
      />
    </.form_row_compact>
    """
  end

  attr(:conn, :any, required: true)
  attr(:field, :atom, required: true)
  attr(:resource, :string, required: true)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :any, required: true)
  attr(:field_type_map, :map, required: true)
  attr(:belongs_to_fields, :map, required: true)
  attr(:collections, :map, required: true)

  defp vertical_field(assigns) do
    assigns = assign(assigns, :kind, field_kind(assigns))

    ~H"""
    <div class="m-4">
      <.live_select_embed
        :if={@kind == :live_select}
        conn={@conn}
        field={@field}
        resource={@resource}
        type={@type}
        changeset={@changeset}
        data={@data}
        belongs_to_fields={@belongs_to_fields}
        no_label={false}
      />
      <.form_select
        :if={@kind == :belongs_to}
        type={@type}
        resource={@resource}
        field={@field}
        changeset={@changeset}
        data={@data}
        options={@belongs_to_fields[@field][:data]}
        belongs_to={true}
        select_type={@field_type_map[@field] || :select}
      />
      <.form_select
        :if={@kind == :collection}
        type={@type}
        resource={@resource}
        field={@field}
        changeset={@changeset}
        data={@data}
        options={@collections[@field]}
        belongs_to={false}
        select_type={@field_type_map[@field] || :select}
      />
      <.form_input
        :if={@kind == :input}
        type={@type}
        resource={@resource}
        field={@field}
        changeset={@changeset}
        field_type_map={@field_type_map}
        data={@data}
      />
    </div>
    """
  end

  attr(:conn, :any, required: true)
  attr(:field, :atom, required: true)
  attr(:resource, :string, required: true)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :any, required: true)
  attr(:belongs_to_fields, :map, required: true)
  attr(:no_label, :boolean, required: true)

  defp live_select_embed(assigns) do
    field_id = :"#{to_string(assigns.field)}_id"

    initial_value =
      if assigns.type == "edit" do
        Map.get(assigns.changeset.changes, field_id) ||
          Map.get(assigns.changeset.data, field_id) ||
          Map.get(assigns.data, field_id)
      end

    session = %{
      "parent_resource" => assigns.resource,
      "field" => assigns.field,
      "resource" => assigns.belongs_to_fields[assigns.field][:resource],
      "search_fields" => assigns.belongs_to_fields[assigns.field][:search_fields],
      "no_label" => assigns.no_label
    }

    session =
      if initial_value, do: Map.put(session, "initial_value", initial_value), else: session

    assigns = assign(assigns, :session, session)

    ~H"""
    {live_render(@conn, SanbaseWeb.LiveSelect, session: @session)}
    """
  end

  defp field_kind(%{field: field, belongs_to_fields: btf, collections: cols}) do
    cond do
      get_in(btf, [field, :type]) == :live_select -> :live_select
      Map.has_key?(btf, field) -> :belongs_to
      Map.has_key?(cols, field) -> :collection
      true -> :input
    end
  end

  defp form_action("new", resource, _data), do: ~p"/admin/generic?resource=#{resource}"

  defp form_action(_edit, resource, data),
    do: ~p"/admin/generic/#{data}?resource=#{resource}"

  attr(:label, :string, default: nil)
  attr(:for, :string, default: nil)
  attr(:label_width, :string, default: "16rem")
  attr(:input_max_width, :string, default: "40rem")
  slot(:inner_block, required: true)

  defp form_row_compact(assigns) do
    ~H"""
    <div
      class="grid items-center gap-x-6 py-1 grid-cols-[var(--label-w)_1fr] max-md:grid-cols-1 max-md:gap-y-1 max-md:py-2"
      style={"--label-w: #{@label_width};"}
    >
      <label
        :if={@label}
        for={@for}
        class="text-sm font-semibold text-zinc-800 text-right pr-1 max-md:text-left max-md:pr-0"
      >
        {@label}
      </label>
      <div :if={!@label} aria-hidden="true"></div>
      <div class="min-w-0" style={if @input_max_width, do: "max-width: #{@input_max_width}"}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr(:resource, :string, required: true)
  attr(:field, :atom, required: true)
  attr(:field_type_map, :map, required: true)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :map, required: false, default: %{})

  defp form_input_compact(assigns) do
    assigns =
      assign(assigns,
        value: resolve_input_value(assigns),
        input_type: input_html_type(Map.get(assigns.field_type_map, assigns.field)),
        name: assigns.resource <> "[" <> to_string(assigns.field) <> "]",
        id: assigns.resource <> "_" <> to_string(assigns.field)
      )

    ~H"""
    <%= cond do %>
      <% @input_type == "textarea" -> %>
        <textarea
          id={@id}
          name={@name}
          class="block w-full rounded-md border border-zinc-300 px-2 py-1 text-zinc-900 focus:border-zinc-400 focus:ring-0 text-sm leading-5 min-h-[4rem]"
        ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <% @input_type == "checkbox" -> %>
        <input
          type="hidden"
          name={@name}
          value="false"
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={Phoenix.HTML.Form.normalize_value("checkbox", @value)}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
        />
      <% true -> %>
        <input
          type={@input_type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@input_type, @value)}
          onwheel="this.blur()"
          class="block w-full rounded-md border border-zinc-300 px-2 py-1 text-zinc-900 focus:border-zinc-400 focus:ring-0 text-sm leading-5"
        />
    <% end %>
    """
  end

  attr(:resource, :string, required: true)
  attr(:field, :atom, required: true)
  attr(:options, :list, required: true)
  attr(:select_type, :atom, required: false, default: :select)
  attr(:belongs_to, :boolean, required: false, default: false)
  attr(:type, :string, required: true)
  attr(:changeset, :map, required: true)
  attr(:data, :map, required: false, default: %{})

  defp form_select_compact(assigns) do
    assigns =
      assign(assigns,
        name:
          select_name(assigns.resource, assigns.field, assigns.belongs_to, assigns.select_type),
        id: assigns.resource <> "_" <> to_string(assigns.field),
        value: select_value(assigns),
        prompt: select_prompt(assigns.options, assigns.field),
        multiple: assigns.select_type == :multiselect
      )

    ~H"""
    <select
      id={@id}
      name={@name}
      class="block w-full rounded-md border border-gray-300 bg-white shadow-sm px-2 py-1 text-sm leading-5 focus:border-zinc-400 focus:ring-0"
      multiple={@multiple}
      size={if @multiple, do: 12}
    >
      <option :if={@prompt} value="">{@prompt}</option>
      {Phoenix.HTML.Form.options_for_select(@options, @value)}
    </select>
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
  attr(:data, :map, required: false, default: %{})

  def form_select(assigns) do
    assigns =
      assign(assigns,
        name:
          select_name(assigns.resource, assigns.field, assigns.belongs_to, assigns.select_type),
        value: select_value(assigns),
        prompt: select_prompt(assigns.options, assigns.field)
      )

    ~H"""
    <.input
      name={@name}
      id={@resource <> "_" <> to_string(@field)}
      label={humanize(@field)}
      type="select"
      multiple={@select_type == :multiselect}
      options={@options}
      value={@value}
      prompt={@prompt}
    />
    """
  end

  defp select_name(resource, field, belongs_to?, select_type) do
    suffix = if belongs_to?, do: "_id", else: ""
    multi = if select_type == :multiselect, do: "[]", else: ""
    resource <> "[" <> to_string(field) <> suffix <> "]" <> multi
  end

  defp select_value(%{field: field, belongs_to: belongs_to?, changeset: cs} = assigns) do
    value_field =
      if belongs_to?, do: String.to_existing_atom(to_string(field) <> "_id"), else: field

    lookup_field(value_field, cs.changes, cs.data, Map.get(assigns, :data, %{}))
  end

  defp select_prompt(options, field) do
    if length(options) == 1, do: nil, else: "Select #{humanize(field)}"
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
  attr(:singular, :string, required: true)
  attr(:fields, :list, required: true)
  attr(:assocs, :map, required: false, default: %{})
  attr(:data, :map, required: true)
  attr(:funcs, :map, required: false, default: %{})
  attr(:field_type_map, :map, required: true)

  def show_table(assigns) do
    ~H"""
    <div class="mt-4">
      <h3 class="text-2xl font-medium text-gray-700 mb-2">
        Show {@singular}
      </h3>
      <div class="relative shadow-md sm:rounded-lg">
        <div class="overflow-x-auto">
          <table class="w-full text-xs text-left rtl:text-right text-gray-500 dark:text-gray-400 min-w-full table-fixed">
            <tbody>
              <%= for field <- @fields do %>
                <tr class="hover:bg-gray-50 dark:hover:bg-gray-600">
                  <th class="text-xs px-2 py-1 text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400 border-b border-gray-200 whitespace-nowrap w-1/4">
                    {to_string(field)}
                  </th>
                  <.td_show
                    class="px-3 py-2 border-b border-gray-200 whitespace-pre-wrap break-words"
                    value={
                      resolve_field_value(@data, field, @assocs[@data.id], @funcs, @field_type_map)
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

  attr(:actions, :list, required: false, default: [])
  attr(:resource, :string, required: true)
  attr(:resource_name, :string, required: true)
  attr(:singular, :string, required: false)
  attr(:create_link_kv, :list, required: false, default: [])
  attr(:fields, :list, required: true)
  attr(:rows, :list, required: true)
  attr(:funcs, :map, required: false, default: %{})

  def has_many_table(assigns) do
    ~H"""
    <div class="table-responsive">
      <div class="m-4 flex flex-col gap-x-10">
        <h3 class="text-3xl font-medium text-gray-700 mb-2">{@resource_name}</h3>
        <%= if @create_link_kv != [] do %>
          <.new_resource_button
            resource={@resource}
            singular={@singular}
            create_link_kv={@create_link_kv}
          />
        <% end %>
      </div>
      <div class="relative overflow-x-auto shadow-md sm:rounded-lg">
        <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
          <.thead fields={@fields} field_type_map={%{}} actions={[]} />
          <.tbody
            resource={@resource}
            rows={@rows}
            fields={@fields}
            assocs={%{}}
            field_type_map={%{}}
            actions={@actions |> Enum.filter(&(&1 in [:edit, :delete]))}
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
  attr(:singular, :string, required: false, default: nil)
  attr(:custom_index_actions, :list, required: false, default: nil)

  def table(assigns) do
    ~H"""
    <div class="table-responsive flex-1 flex flex-col min-h-0">
      <div class="m-4 flex flex-row items-center">
        <%= if :new in @actions do %>
          <.new_resource_button resource={@resource} singular={@singular} />
        <% end %>

        <div class="flex-1"></div>

        <%= if @custom_index_actions do %>
          <.custom_index_actions actions={@custom_index_actions} />
        <% end %>
      </div>
      <div class="relative shadow-md sm:rounded-lg flex-1 flex flex-col min-h-0">
        <div class="overflow-y-auto flex-1">
          <table class="w-full text-xs text-left rtl:text-right text-gray-500 dark:text-gray-400">
            <.thead fields={@fields} field_type_map={@field_type_map} actions={@actions} />
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
          <th
            scope="col"
            class={
              [
                "px-2 py-1 whitespace-nowrap",
                # Make ID and boolean columns narrower
                if(field == :id or Map.get(@field_type_map, field) == :boolean, do: "w-[80px]")
              ]
            }
          >
            {field}
          </th>
        <% end %>
        <%= if @actions do %>
          <th scope="col" class="px-2 py-1 whitespace-nowrap w-[160px]">Actions</th>
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
                resolve_field_value(row, field, @assocs[row.id], @funcs, @field_type_map)
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
      <button type={@type} class={btn_classes(@color, @size)}>
        {@label}
      </button>
    </.link>
    """
  end

  defp btn_classes(color, size) do
    base = "font-medium rounded-lg me-2 mb-2 focus:ring-4"
    size_classes = if size == :small, do: "text-xs px-4 py-2", else: "text-sm px-5 py-2.5"

    color_classes =
      case color do
        :blue ->
          "text-white bg-blue-700 hover:bg-blue-800 focus:ring-blue-300"

        :yellow ->
          "focus:outline-none text-white bg-yellow-400 hover:bg-yellow-500 focus:ring-yellow-300"

        :red ->
          "focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-red-300"

        :white ->
          "text-gray-900 focus:outline-none bg-white border border-gray-200 hover:bg-gray-100 hover:text-blue-700 focus:ring-gray-100"
      end

    "#{base} #{size_classes} #{color_classes}"
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
  attr(:singular, :string, required: false)
  attr(:create_link_kv, :list, required: false, default: [])

  def new_resource_button(assigns) do
    assigns =
      if assigns[:singular] do
        assigns
      else
        assign(assigns, :singular, assigns.resource)
      end

    ~H"""
    <button
      type="button"
      class="text-white w-fit p-2 bg-blue-500 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
    >
      <.link href={~p"/admin/generic/new?#{Keyword.merge([resource: @resource], @create_link_kv)}"}>
        <.icon name="hero-plus-circle" /> Add new {@singular}
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
      action={~p"/admin/generic/#{@row}?resource=#{@resource}"}
      method="post"
      class="inline-block"
      data-confirm="Are you sure you want to delete this?"
    >
      <input type="hidden" name="_method" value="delete" />
      <button type="submit" class="text-red-600 hover:text-red-800 px-2 py-1 rounded">
        <.icon name="hero-trash" class="w-4 h-4" />
      </button>
    </.form>
    """
  end

  def index_action_btn(assigns) do
    ~H"""
    <button class={[
      "px-2 py-1 rounded inline-flex items-center",
      case @action do
        :edit -> "text-yellow-600 hover:text-yellow-800"
        :show -> "text-blue-600 hover:text-blue-800"
      end
    ]}>
      <.link href={generic_admin_action_path(@action, @row, @resource)}>
        <.icon
          name={
            case @action do
              :edit -> "hero-pencil"
              :show -> "hero-eye"
            end
          }
          class="w-4 h-4"
        />
      </.link>
    </button>
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
      href={~p"/admin/generic?resource=#{@resource}"}
      label={@label}
      color={@color}
    />
    """
  end

  attr(:value, :string, required: true)

  def td_index(assigns) do
    ~H"""
    <td class="px-3 py-2 whitespace-nowrap overflow-hidden text-ellipsis" style="max-width: 200px;">
      {@value}
    </td>
    """
  end

  attr(:value, :string, required: true)
  attr(:class, :string, required: false, default: "")

  def td_show(assigns) do
    ~H"""
    <td class={@class}>
      {@value}
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
      href={~p"/admin/generic/#{@row}?resource=#{@resource}"}
      class="underline"
    >
      {@label}
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
        Showing {@current_page * @page_size + 1} to {Enum.min([
          (@current_page + 1) * @page_size,
          @rows_count
        ])} of {@rows_count} entries
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
        ~p"/admin/generic?#{%{resource: resource, page: page_number}}"

      :search ->
        ~p"/admin/generic/search?#{%{"resource" => resource, "page" => page_number, "search" => search}}"
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
        filters: normalize_filters(assigns.search),
        showError: false
      })
    }>
      <div class="flex flex-col gap-2">
        <.form
          for={%{}}
          as={:search}
          method="get"
          action={~p"/admin/generic/search?resource=#{@resource}"}
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
                              {field}
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
            href={~p"/admin/generic?resource=#{@resource}"}
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
    <h1 class="text-2xl font-bold">
      {Sanbase.Utils.Inflect.camelize(@resource)}
    </h1>
    """
  end

  @doc """
  Renders custom index action buttons.

  ## Attributes
  - `:actions` - List of maps containing custom action definitions with :name and :path keys

  ## Example
  ```elixir
  <.custom_index_actions actions={[%{name: "Export", path: "/export"}]} />
  ```
  """
  attr(:actions, :list, required: true)

  def custom_index_actions(assigns) do
    ~H"""
    <%= for action <- @actions do %>
      <.btn href={action.path} label={action.name} color={:blue} />
    <% end %>
    """
  end

  # private

  defp generic_admin_action_path(:show, row, resource),
    do: ~p"/admin/generic/#{row}?resource=#{resource}"

  defp generic_admin_action_path(:edit, row, resource),
    do: ~p"/admin/generic/#{row}/edit?resource=#{resource}"

  # Resolves the value to render for a single field of an admin record.
  #
  # Lookup order: belongs_to_links (precomputed link) -> raw record field -> value_modifier override.
  # The final value is then formatted based on its Ecto type.
  #
  # Parameters:
  #   record               - the Ecto struct / map being rendered (e.g. a User, a Project)
  #   field                - atom field name to display (e.g. :email, :user_id)
  #   belongs_to_links     - map %{field_atom => rendered_link} built by
  #                          GenericAdminController.LinkBuilder for this record's
  #                          belongs_to associations. When present for `field`, the
  #                          link replaces the raw FK value (e.g. :user_id -> <a>..</a>).
  #   value_modifier_funcs - map %{field_atom => (record -> any)} of `value_modifier`
  #                          functions taken from the resource's `:fields_override`
  #                          config. When present for `field`, called with the full
  #                          record to produce the display value.
  #   field_type_map       - map %{field_atom => ecto_type} used for formatting:
  #                            :map / :list -> Jason-encoded string
  #                            :boolean     -> green check / red x icon
  #                            anything else -> value as-is
  defp resolve_field_value(record, field, belongs_to_links, value_modifier_funcs, field_type_map) do
    result =
      if belongs_to_links[field], do: belongs_to_links[field], else: Map.get(record, field)

    result =
      if value_modifier_funcs[field],
        do: value_modifier_funcs[field].(record),
        else: result

    case Map.get(field_type_map, field) do
      type when type in [:map, :list] ->
        if is_binary(result), do: result, else: Jason.encode!(result)

      :boolean ->
        if result == true,
          do: Phoenix.HTML.raw(~s(<span class="hero-check-circle text-green-500"></span>)),
          else: Phoenix.HTML.raw(~s(<span class="hero-x-circle text-red-500"></span>))

      _ ->
        result
    end
  end

  defp normalize_filters(search) do
    (Map.get(search || %{}, "filters") || [])
    |> case do
      filters when is_map(filters) and map_size(filters) > 0 ->
        filters
        |> Map.to_list()
        |> Enum.map(fn {_key, filter} -> filter end)

      filters when is_list(filters) and filters != [] ->
        filters

      _ ->
        [%{"field" => "Fields", "value" => ""}]
    end
  end
end
