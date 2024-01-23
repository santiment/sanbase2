defmodule SanbaseWeb.GenericController do
  use SanbaseWeb, :controller

  import Ecto.Query

  alias SanbaseWeb.Router.Helpers, as: Routes
  alias Sanbase.Repo

  @resource_module_map SanbaseWeb.GenericAdmin.resource_module_map()

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

  def search(
        conn,
        %{"search" => %{"generic_search" => search_text, "resource" => resource}} = params
      ) do
    module = module_from_resource(resource)
    preloads = @resource_module_map[resource][:preloads] || []
    page = to_integer(params["page"] || 0)
    page_size = to_integer(params["page_size"] || 10)

    {total_rows, paginated_rows} =
      case parse_field_value(search_text) do
        {:ok, field, value} ->
          search_by_field_value(module, field, value, preloads, page, page_size)

        :error ->
          case Integer.parse(search_text) do
            {id, ""} -> search_by_id(module, id, preloads)
            _ -> search_by_text(module, String.downcase(search_text))
          end
      end

    render(conn, "index.html",
      table:
        resource_to_table_params(resource, %{
          total_rows: total_rows,
          rows: paginated_rows,
          page: page,
          page_size: page_size,
          search_text: search_text
        })
    )
  end

  def show(conn, %{"resource" => resource, "id" => id}) do
    module = module_from_resource(resource)
    admin_module = @resource_module_map[resource][:admin_module]
    data = Repo.get(module, id)

    render(conn, "show.html",
      resource: resource,
      data: data,
      string_fields: string_fields(module),
      belongs_to: apply(admin_module, :belongs_to, [data]),
      has_many: apply(admin_module, :has_many, [data])
    )
  end

  def edit(conn, %{"resource" => resource, "id" => id}) do
    module = module_from_resource(resource)
    data = Repo.get(module, id)
    changeset = module.changeset(data, %{})

    render(conn, "edit.html",
      resource: resource,
      data: data,
      action: Routes.generic_path(conn, :update, data, resource: resource),
      edit_fields: @resource_module_map[resource][:edit_fields],
      changeset: changeset
    )
  end

  def update(conn, %{"id" => id, "resource" => resource} = params) do
    module = module_from_resource(resource)
    data = Repo.get(module, id)
    changes = params[@resource_module_map[resource][:singular]]
    changeset = module.changeset(data, changes)

    case Sanbase.Repo.update(changeset) do
      {:ok, response_resource} ->
        conn
        |> put_flash(:info, "#{resource} updated successfully.")
        |> redirect(to: Routes.generic_path(conn, :show, response_resource, resource: resource))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html",
          resource: resource,
          data: data,
          action: Routes.generic_path(conn, :update, data, resource: resource),
          edit_fields: @resource_module_map[resource][:edit_fields],
          changeset: changeset
        )
    end
  end

  def show_action(conn, %{"action" => action, "resource" => resource, "id" => id}) do
    admin_module = @resource_module_map[resource][:admin_module]
    apply(admin_module, String.to_existing_atom(action), [conn, %{resource: resource, id: id}])
  end

  # private

  def module_from_resource(resource), do: @resource_module_map[resource][:module]

  def resource_to_table_params(resource, params) do
    name = String.capitalize(resource)
    module = @resource_module_map[resource][:module]
    preloads = @resource_module_map[resource][:preloads] || []
    funcs = @resource_module_map[resource][:funcs] || %{}
    rows = params[:rows]
    page = to_integer(params[:page])
    page_size = to_integer(params[:page_size])

    index_fields =
      case @resource_module_map[resource][:index_fields] do
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

    %{
      resource: resource,
      resource_name: name,
      rows: fetched_rows,
      rows_count: total_count,
      fields: index_fields,
      funcs: funcs,
      actions: @resource_module_map[resource][:actions],
      current_page: page,
      page_size: page_size,
      action: action,
      search_text: params[:search_text] || ""
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

  defp string_fields(module) do
    fields(module)
  end

  def parse_field_value(str) do
    case Regex.run(~r/(\S+)\s*=\s*(\S+)/, str) do
      [_, field, value] -> {:ok, field, value}
      _ -> :error
    end
  end

  def search_by_field_value(module, field, value, preloads, page, page_size) do
    case Integer.parse(value) do
      {id, ""} ->
        {1, search_by_id(module, id, preloads)}

      _ ->
        value = String.trim(value)

        value = "%" <> value <> "%"
        field = String.to_existing_atom(field)

        field_type = module.__schema__(:type, field)
        sort_field = sort_field(module)

        query =
          if field_type == :string do
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
end
