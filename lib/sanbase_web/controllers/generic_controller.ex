defmodule SanbaseWeb.GenericController do
  use SanbaseWeb, :controller

  import Ecto.Query

  alias SanbaseWeb.Router.Helpers, as: Routes
  alias Sanbase.Repo
  alias SanbaseWeb.GenericAdmin

  def resource_module_map() do
    SanbaseWeb.GenericAdmin.resource_module_map()
  end

  def home(conn, _params) do
    render(conn, :home, search_value: "")
  end

  def all_routes do
    (resources_to_routes() ++ custom_routes()) |> Enum.sort()
  end

  def custom_routes do
    [
      {"Webinars", ~p"/admin2/webinars"},
      {"Sheets Templates", ~p"/admin2/sheets_templates/"},
      {"Reports", ~p"/admin2/reports"},
      {"Custom Plans", ~p"/admin2/custom_plans"},
      {"Monitored Twitter Handles", ~p"/admin2/monitored_twitter_handle_live"}
    ]
  end

  def resources_to_routes do
    SanbaseWeb.GenericAdmin.resources()
    |> Enum.map(fn resource ->
      resource_name =
        String.split(resource, [" ", "_", "-"])
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      {resource_name, ~p"/admin2/generic?resource=#{resource}"}
    end)
  end

  def index(conn, %{"resource" => resource} = params) do
    page = params["page"] || 0
    page_size = params["page_size"] || 10

    render(conn, "index.html",
      table: resource_to_table_params(resource, %{page: page, page_size: page_size})
    )
  end

  def index(conn, _) do
    render(conn, "error.html")
  end

  def new(conn, %{"resource" => resource} = params) do
    module = module_from_resource(resource)
    action = Routes.generic_path(conn, :create, resource: resource)
    form_fields = resource_module_map()[resource][:new_fields] || []
    field_type_map = field_type_map(resource, module)
    belongs_to_fields = resource_module_map()[resource][:belongs_to_fields] || %{}
    belongs_to_fields = transform_belongs_to(belongs_to_fields, params)
    collections = resource_module_map()[resource][:collections] || %{}

    changeset = module.changeset(struct(module), %{})

    render(conn, "new.html",
      resource: resource,
      action: action,
      form_fields: form_fields,
      field_type_map: field_type_map,
      changeset: changeset,
      belongs_to_fields: belongs_to_fields,
      collections: collections,
      data: %{}
    )
  end

  def create(conn, %{"resource" => resource} = params) do
    module = module_from_resource(resource)
    field_type_map = field_type_map(resource, module)
    changes = params[resource]

    changes =
      Enum.map(changes, fn {field, value} ->
        case Map.get(field_type_map, String.to_existing_atom(field)) do
          :map -> {field, Jason.decode!(value)}
          _ -> {field, value}
        end
      end)
      |> Enum.into(%{})

    changeset_function =
      if function_exported?(module, :create_changeset, 2), do: :create_changeset, else: :changeset

    changeset = apply(module, changeset_function, [struct(module), changes])
    form_fields = resource_module_map()[resource][:new_fields] || []
    action = Routes.generic_path(conn, :create, resource: resource)
    belongs_to_fields = resource_module_map()[resource][:belongs_to_fields] || %{}
    belongs_to_fields = transform_belongs_to(belongs_to_fields, params)
    collections = resource_module_map()[resource][:collections] || %{}

    case Sanbase.Repo.insert(changeset) do
      {:ok, response_resource} ->
        conn
        |> put_flash(:info, "#{resource} created successfully.")
        |> redirect(to: Routes.generic_path(conn, :show, response_resource, resource: resource))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html",
          resource: resource,
          action: action,
          form_fields: form_fields,
          changeset: changeset,
          field_type_map: field_type_map,
          belongs_to_fields: belongs_to_fields,
          collections: collections,
          data: %{}
        )
    end
  end

  def search(
        conn,
        %{"resource" => resource, "field" => field, "value" => value} = params
      ) do
    module = module_from_resource(resource)
    preloads = resource_module_map()[resource][:preloads] || []
    page = to_integer(params["page"] || 0)
    page_size = to_integer(params["page_size"] || 10)

    {total_rows, paginated_rows} =
      search_by_field_value(module, resource, field, value, preloads, page, page_size)

    render(conn, "index.html",
      table:
        resource_to_table_params(resource, %{
          total_rows: total_rows,
          rows: paginated_rows,
          page: page,
          page_size: page_size
        })
    )
  end

  def show(conn, %{"resource" => resource, "id" => id}) do
    module = module_from_resource(resource)
    admin_module = resource_module_map()[resource][:admin_module]
    data = Repo.get(module, id) |> Repo.preload(resource_module_map()[resource][:preloads] || [])
    funcs = resource_module_map()[resource][:funcs] || %{}
    field_type_map = field_type_map(resource, module)
    extra_show_fields = resource_module_map()[resource][:extra_show_fields] || []
    actions = resource_module_map()[resource][:actions] || []

    assocs =
      Enum.map([data], fn row ->
        {row.id, SanbaseWeb.GenericController.LinkBuilder.build_link(module, row)}
      end)
      |> Map.new()

    data =
      GenericAdmin.call_module_function_or_default(admin_module, :before_filter, [data], data)

    render(conn, "show.html",
      resource: resource,
      data: data,
      assocs: assocs,
      funcs: funcs,
      fields: fields(module) ++ extra_show_fields,
      field_type_map: field_type_map,
      actions: actions,
      belongs_to:
        GenericAdmin.call_module_function_or_default(admin_module, :belongs_to, [data], []),
      has_many: GenericAdmin.call_module_function_or_default(admin_module, :has_many, [data], [])
    )
  end

  def edit(conn, %{"resource" => resource, "id" => id} = params) do
    module = module_from_resource(resource)
    admin_module = resource_module_map()[resource][:admin_module]
    data = Repo.get(module, id)
    changeset = module.changeset(data, %{})
    form_fields = resource_module_map()[resource][:edit_fields] || []
    action = Routes.generic_path(conn, :update, data, resource: resource)
    field_type_map = field_type_map(resource, module)
    belongs_to_fields = resource_module_map()[resource][:belongs_to_fields] || %{}
    belongs_to_fields = transform_belongs_to(belongs_to_fields, params)
    collections = resource_module_map()[resource][:collections] || %{}

    data =
      GenericAdmin.call_module_function_or_default(admin_module, :before_filter, [data], data)

    render(conn, "edit.html",
      resource: resource,
      data: data,
      action: action,
      form_fields: form_fields,
      field_type_map: field_type_map,
      changeset: changeset,
      belongs_to_fields: belongs_to_fields,
      collections: collections
    )
  end

  def update(conn, %{"id" => id, "resource" => resource} = params) do
    module = module_from_resource(resource)
    admin_module = resource_module_map()[resource][:admin_module]
    data = Repo.get(module, id)
    field_type_map = field_type_map(resource, module)
    changes = params[resource]

    changes =
      Enum.map(changes, fn {field, value} ->
        case Map.get(field_type_map, String.to_existing_atom(field)) do
          :map -> {field, Jason.decode!(value)}
          _ -> {field, value}
        end
      end)
      |> Enum.into(%{})

    changeset_function =
      if function_exported?(module, :update_changeset, 2), do: :update_changeset, else: :changeset

    changeset = apply(module, changeset_function, [data, changes])
    form_fields = resource_module_map()[resource][:edit_fields] || []
    action = Routes.generic_path(conn, :update, data, resource: resource)
    belongs_to_fields = resource_module_map()[resource][:belongs_to_fields] || %{}
    belongs_to_fields = transform_belongs_to(belongs_to_fields, params)
    collections = resource_module_map()[resource][:collections] || %{}

    case Sanbase.Repo.update(changeset) do
      {:ok, response_resource} ->
        GenericAdmin.call_module_function_or_default(
          admin_module,
          :after_filter,
          [response_resource, changes],
          :ok
        )
        |> case do
          {:error, error} ->
            conn
            |> put_flash(:error, "Some of the fields were not updated: #{error}")
            |> redirect(
              to: Routes.generic_path(conn, :show, response_resource, resource: resource)
            )

          _ ->
            conn
            |> put_flash(:info, "#{resource} updated successfully.")
            |> redirect(
              to: Routes.generic_path(conn, :show, response_resource, resource: resource)
            )
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html",
          resource: resource,
          data: data,
          action: action,
          form_fields: form_fields,
          changeset: changeset,
          field_type_map: field_type_map,
          belongs_to_fields: belongs_to_fields,
          collections: collections
        )
    end
  end

  def show_action(conn, %{"action" => action, "resource" => resource, "id" => id}) do
    admin_module = resource_module_map()[resource][:admin_module]
    apply(admin_module, String.to_existing_atom(action), [conn, %{resource: resource, id: id}])
  end

  # private

  def module_from_resource(resource), do: resource_module_map()[resource][:module]

  def resource_to_table_params(resource, params) do
    name = String.capitalize(resource)
    module = resource_module_map()[resource][:module]
    admin_module = resource_module_map()[resource][:admin_module]
    preloads = resource_module_map()[resource][:preloads] || []
    funcs = resource_module_map()[resource][:funcs] || %{}
    rows = params[:rows]
    page = to_integer(params[:page])
    page_size = to_integer(params[:page_size])
    field_type_map = field_type_map(resource, module)

    index_fields =
      case resource_module_map()[resource][:index_fields] do
        nil -> fields(module)
        :all -> fields(module)
        fields when is_list(fields) -> fields
      end

    total_count =
      case rows do
        nil -> Repo.aggregate(module, :count, :id)
        _ -> params[:total_rows]
      end

    action =
      case rows do
        nil -> :index
        _ -> :search
      end

    offset = page * page_size

    fetched_rows =
      case rows do
        nil ->
          sort_field = sort_field(module)

          Repo.all(
            from(m in module,
              order_by: [desc: field(m, ^sort_field)],
              preload: ^preloads,
              limit: ^page_size,
              offset: ^offset
            )
          )

        _ ->
          rows
      end

    fetched_rows =
      Enum.map(
        fetched_rows,
        &GenericAdmin.call_module_function_or_default(admin_module, :before_filter, [&1], &1)
      )

    assocs =
      Enum.map(fetched_rows, fn row ->
        {row.id, SanbaseWeb.GenericController.LinkBuilder.build_link(module, row)}
      end)
      |> Map.new()

    %{
      resource: resource,
      resource_name: name,
      rows: fetched_rows,
      rows_count: total_count,
      fields: index_fields,
      funcs: funcs,
      actions: resource_module_map()[resource][:actions],
      current_page: page,
      page_size: page_size,
      action: action,
      search_text: "",
      assocs: assocs,
      field_type_map: field_type_map
    }
  end

  def all(module, preloads \\ []) do
    from(
      m in module,
      order_by: [desc: m.id],
      limit: 10
    )
    |> Repo.all()
    |> Repo.preload(preloads)
  end

  defp search_by_text(module, text) do
    module.by_search_text(text)
  end

  defp search_by_id(module, id, preloads) do
    case Repo.get(module, id) do
      nil ->
        []

      result ->
        result = Repo.preload(result, preloads)
        [result]
    end
  end

  def fields(module) do
    module.__schema__(:fields)
  end

  def parse_field_value(str) do
    case Regex.run(~r/(\S+)\s*=\s*(\S+)/, str) do
      [_, field, value] -> {:ok, field, value}
      _ -> :error
    end
  end

  def search_by_field_value(module, resource, field, value, preloads, page, page_size) do
    search_fields_map = resource_module_map()[resource][:search_fields] || %{}
    search_fields = Map.keys(search_fields_map) |> Enum.map(&Atom.to_string/1)

    case field do
      "id" ->
        {id, ""} = Integer.parse(value)
        {1, search_by_id(module, id, preloads)}

      field ->
        if field in search_fields do
          query = search_fields_map[String.to_existing_atom(field)]
          total_rows = Repo.aggregate(query, :count, :id)

          paginated_rows =
            query
            |> limit(^page_size)
            |> offset(^(page_size * page))
            |> Repo.all()

          {total_rows, paginated_rows}
        else
          value = String.trim(value)

          field = String.to_existing_atom(field)

          field_type = module.__schema__(:type, field)
          sort_field = sort_field(module)

          query =
            if field_type == :string do
              value = "%" <> value <> "%"

              from(m in module,
                where: like(field(m, ^field), ^value),
                preload: ^preloads,
                order_by: [desc: field(m, ^sort_field)]
              )
            else
              from(m in module,
                where: field(m, ^field) == ^value,
                preload: ^preloads,
                order_by: [desc: field(m, ^sort_field)]
              )
            end

          total_rows = Repo.aggregate(query, :count, :id)

          paginated_rows =
            query
            |> limit(^page_size)
            |> offset(^(page_size * page))
            |> Repo.all()

          {total_rows, paginated_rows}
        end
    end
  end

  def sort_field(module) do
    fields = fields(module)

    cond do
      :id in fields -> :id
      :inserted_at in fields -> :inserted_at
      true -> raise("Ecto schema module #{module} does not have :id or :inserted_at fields")
    end
  end

  def to_integer(value) do
    case value do
      nil -> nil
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  def field_type_map(resource, module) do
    field_type_map = field_type_map(module)
    field_type_overwrite = resource_module_map()[resource][:field_types] || %{}
    Map.merge(field_type_map, field_type_overwrite)
  end

  def field_type_map(module) do
    module.__schema__(:fields)
    |> Enum.map(&{&1, module.__schema__(:type, &1)})
    |> Enum.into(%{})
  end

  def transform_belongs_to(belongs_to_fields, params) do
    Enum.map(belongs_to_fields, fn
      {field, %{query: query, transform: transform} = metadata} ->
        if params["linked_resource"] && params["linked_resource_id"] &&
             params["linked_resource"] == to_string(field) do
          query = query |> where([p], p.id == ^params["linked_resource_id"])
          data = Repo.all(query) |> transform.()
          {field, %{data: data, type: :select}}
        else
          {field,
           %{
             type: :live_select,
             resource: metadata[:resource],
             search_fields: metadata[:search_fields]
           }}
        end

      {field, metadata} ->
        {field,
         %{
           type: :live_select,
           resource: metadata[:resource],
           search_fields: metadata[:search_fields]
         }}
    end)
    |> Enum.into(%{})
  end
end

defmodule SanbaseWeb.GenericController.LinkBuilder do
  def build_link(module, record) do
    module.__schema__(:associations)
    |> Enum.reduce(%{}, fn assoc_name, acc ->
      assoc_info = module.__schema__(:association, assoc_name)

      case assoc_info do
        %Ecto.Association.BelongsTo{related: related_module} ->
          field_name = :"#{assoc_name}_id"
          field_value = Map.get(record, field_name)

          if is_nil(field_value) do
            Map.put(acc, to_string(assoc_name), nil)
          else
            resource = module_to_resource_name(related_module)
            link = href(resource, field_value, "#{field_name}: #{field_value}")
            Map.put(acc, field_name, link)
          end

        _ ->
          acc
      end
    end)
  end

  defp href(resource, id, label) do
    relative_url =
      SanbaseWeb.Router.Helpers.generic_path(SanbaseWeb.Endpoint, :show, id, resource: resource)

    Phoenix.HTML.Link.link(label, to: relative_url, class: "text-blue-600 hover:text-blue-800")
  end

  defp module_to_resource_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> Inflex.pluralize()
  end
end
