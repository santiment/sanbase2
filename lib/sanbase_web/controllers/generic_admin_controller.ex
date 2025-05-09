defmodule SanbaseWeb.GenericAdminController do
  use SanbaseWeb, :controller

  import Ecto.Query

  alias SanbaseWeb.Router.Helpers, as: Routes
  alias Sanbase.Repo
  alias SanbaseWeb.GenericAdmin

  def resource_module_map(%Plug.Conn{} = conn) do
    SanbaseWeb.GenericAdmin.resource_module_map(conn)
  end

  def all_routes(conn \\ nil) do
    sorted_routes = (resources_to_routes() ++ custom_routes()) |> Enum.sort()

    case conn do
      %{assigns: %{current_user: user}} ->
        [{"Logout (#{user.email})", ~p"/admin_auth/logout"}] ++ sorted_routes

      %{assigns: _} ->
        [{"Authenticate", ~p"/admin_auth/login"}] ++ sorted_routes

      _ ->
        # If the conn is not provided then we're in the cond do
        # where we filter the routes in a search operation. Do not return
        # neither Authenticate, nor Logout
        sorted_routes
    end
  end

  def custom_routes do
    [
      {"Webinars", ~p"/admin/webinars"},
      {"Sheets Templates", ~p"/admin/sheets_templates/"},
      {"Reports", ~p"/admin/reports"},
      {"Custom Plans", ~p"/admin/custom_plans"},
      {"Monitored Twitter Handles", ~p"/admin/monitored_twitter_handle_live"},
      {"Tweets Prediction", ~p"/admin/tweets_prediction"},
      {"Ecosystem Project Labels Suggestions", ~p"/forms/suggest_ecosystems"},
      {"User Forms", ~p"/forms"},
      {"Admin Forms", ~p"/admin/admin_forms"},
      {"Metric Registry", ~p"/admin/metric_registry"}
    ]
  end

  def resources_to_routes do
    SanbaseWeb.GenericAdmin.resources()
    |> Enum.map(fn resource ->
      resource_name =
        String.split(resource, [" ", "_", "-"])
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      {resource_name, ~p"/admin/generic?resource=#{resource}"}
    end)
  end

  def home(%Plug.Conn{} = conn, _params) do
    render(conn, :home, search_value: "")
  end

  def index(%Plug.Conn{} = conn, %{"resource" => resource} = params) do
    page = params["page"] || 0
    page_size = params["page_size"] || 10

    render(%Plug.Conn{} = conn, "index.html",
      table: resource_to_table_params(conn, resource, %{page: page, page_size: page_size})
    )
  end

  def index(%Plug.Conn{} = conn, _) do
    render(conn, "error.html")
  end

  def new(%Plug.Conn{} = conn, %{"resource" => resource} = params) do
    module = module_from_resource(conn, resource)
    changeset = module.changeset(struct(module), %{})

    args =
      %{
        changeset: changeset,
        data: %{}
      }
      |> Map.merge(resource_params(conn, resource, :new, params))
      |> Keyword.new()

    render(conn, "new.html", args)
  end

  def create(%Plug.Conn{} = conn, %{"resource" => resource} = params) do
    module = module_from_resource(conn, resource)
    admin_module = resource_module_map(conn)[resource][:admin_module]
    resource_params = resource_params(conn, resource, :new, params)

    field_type_map = resource_params.field_type_map

    changes = transform_changes(params[resource], field_type_map)

    changeset_function =
      if function_exported?(module, :create_changeset, 2), do: :create_changeset, else: :changeset

    changeset = apply(module, changeset_function, [struct(module), changes])

    create_and_redirect(conn, changeset, params, changes, resource, admin_module)
  end

  def search(
        %Plug.Conn{} = conn,
        %{"resource" => resource, "search" => %{"filters" => filters}} = params
      ) do
    module = module_from_resource(conn, resource)
    preloads = resource_module_map(conn)[resource][:preloads] || []
    page = to_integer(params["page"] || 0)
    page_size = to_integer(params["page_size"] || 10)

    base_query = from(m in module)

    # Convert map of filters to list and sort by keys to maintain order
    filters_list =
      filters
      |> Map.to_list()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    query =
      Enum.reduce(filters_list, base_query, fn %{"field" => field, "value" => value}, query ->
        case field do
          "id" ->
            {id, ""} = Integer.parse(value)
            where(query, [m], m.id == ^id)

          field ->
            condition = build_field_condition(field, value, module)
            where(query, ^condition)
        end
      end)

    sort_field = sort_field(module)
    query = order_by(query, [m], desc: field(m, ^sort_field))

    total_rows = Repo.aggregate(query, :count, :id)

    paginated_rows =
      query
      |> preload(^preloads)
      |> limit(^page_size)
      |> offset(^(page_size * page))
      |> Repo.all()

    render(conn, "index.html",
      table:
        resource_to_table_params(conn, resource, %{
          total_rows: total_rows,
          rows: paginated_rows,
          page: page,
          page_size: page_size,
          search: params["search"]
        })
    )
  end

  def show(%Plug.Conn{} = conn, %{"resource" => resource, "id" => id}) do
    resource_config = resource_module_map(conn)[resource]
    module = module_from_resource(conn, resource)
    admin_module = resource_config[:admin_module]
    data = Repo.get(module, id) |> Repo.preload(resource_config[:preloads] || [])

    assocs =
      Enum.map([data], fn row ->
        {row.id, SanbaseWeb.GenericAdminController.LinkBuilder.build_link(module, row)}
      end)
      |> Map.new()

    data =
      GenericAdmin.call_module_function_or_default(admin_module, :before_filter, [data], data)

    args =
      %{
        data: data,
        assocs: assocs,
        belongs_to:
          GenericAdmin.call_module_function_or_default(admin_module, :belongs_to, [data], []),
        has_many:
          GenericAdmin.call_module_function_or_default(admin_module, :has_many, [data], [])
      }
      |> Map.merge(resource_params(conn, resource, :show))
      |> Keyword.new()

    render(conn, "show.html", args)
  end

  def edit(%Plug.Conn{} = conn, %{"resource" => resource, "id" => id} = params) do
    module = module_from_resource(conn, resource)
    admin_module = resource_module_map(conn)[resource][:admin_module]
    data = Repo.get(module, id)
    changeset = module.changeset(data, %{})

    data =
      GenericAdmin.call_module_function_or_default(admin_module, :before_filter, [data], data)

    args =
      %{
        changeset: changeset,
        data: data
      }
      |> Map.merge(resource_params(conn, resource, :edit, params))
      |> Keyword.new()

    render(conn, "edit.html", args)
  end

  def update(%Plug.Conn{} = conn, %{"id" => id, "resource" => resource} = params) do
    module = module_from_resource(conn, resource)
    admin_module = resource_module_map(conn)[resource][:admin_module]
    resource_params = resource_params(conn, resource, :update, params)
    data = Repo.get(module, id)
    field_type_map = resource_params.field_type_map

    changes = transform_changes(params[resource], field_type_map)

    changeset_function =
      if function_exported?(module, :update_changeset, 2), do: :update_changeset, else: :changeset

    changeset = apply(module, changeset_function, [data, changes])

    update_and_redirect(conn, changeset, data, params, changes, resource, admin_module)
  end

  def delete(%Plug.Conn{} = conn, %{"id" => id, "resource" => resource}) do
    resource_config = resource_module_map(conn)[resource]
    module = module_from_resource(conn, resource)

    if :delete in resource_config[:actions] do
      Repo.get(module, id)
      |> Repo.delete()
      |> case do
        {:ok, _} ->
          conn
          |> put_flash(:info, "#{resource} item deleted successfully.")
          |> redirect(to: Routes.generic_admin_path(conn, :index, resource: resource))

        {:error, changeset} ->
          conn
          |> put_flash(:error, "Error deleting #{resource}: #{inspect(changeset.errors)}")
          |> redirect(to: Routes.generic_admin_path(conn, :show, id, resource: resource))
      end
    end
  end

  def show_action(%Plug.Conn{} = conn, %{"action" => action, "resource" => resource, "id" => id}) do
    admin_module = resource_module_map(conn)[resource][:admin_module]
    apply(admin_module, String.to_existing_atom(action), [conn, %{resource: resource, id: id}])
  end

  # private

  defp create_and_redirect(conn, changeset, params, changes, resource, admin_module) do
    case Sanbase.Repo.insert(changeset) do
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
            |> put_flash(
              :error,
              "#{resource} created successfully. There was some error after creation: #{error}"
            )
            |> redirect(
              to: Routes.generic_admin_path(conn, :show, response_resource, resource: resource)
            )

          _ ->
            conn
            |> put_flash(:info, "#{resource} created successfully.")
            |> redirect(
              to: Routes.generic_admin_path(conn, :show, response_resource, resource: resource)
            )
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        args =
          %{
            changeset: changeset,
            data: %{}
          }
          |> Map.merge(resource_params(conn, resource, :create, params))
          |> Keyword.new()

        render(conn, "new.html", args)
    end
  end

  defp update_and_redirect(conn, changeset, data, params, changes, resource, admin_module) do
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
              to: Routes.generic_admin_path(conn, :show, response_resource, resource: resource)
            )

          _ ->
            conn
            |> put_flash(:info, "#{resource} updated successfully.")
            |> redirect(
              to: Routes.generic_admin_path(conn, :show, response_resource, resource: resource)
            )
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        args =
          %{
            changeset: changeset,
            data: data
          }
          |> Map.merge(resource_params(conn, resource, :update, params))
          |> Keyword.new()

        render(conn, "edit.html", args)
    end
  end

  defp transform_changes(changes, field_type_map) do
    Enum.map(changes, fn {field, value} ->
      case Map.get(field_type_map, String.to_existing_atom(field)) do
        :map -> {field, Jason.decode!(value)}
        {:array, :string} -> {field, Jason.decode!(value)}
        _ -> {field, value}
      end
    end)
    |> Enum.into(%{})
  end

  defp module_from_resource(%Plug.Conn{} = conn, resource) when is_binary(resource),
    do: resource_module_map(conn)[resource][:module]

  defp resource_to_table_params(%Plug.Conn{} = conn, resource, params) when is_binary(resource) do
    resource_config = resource_module_map(conn)[resource]
    module = resource_config[:module]
    admin_module = resource_config[:admin_module]
    preloads = resource_config[:preloads] || []
    rows = params[:rows]
    page = to_integer(params[:page])
    page_size = to_integer(params[:page_size])

    total_count =
      case rows do
        nil -> Repo.aggregate(module, :count, :id)
        _ -> params[:total_rows]
      end

    action = if rows == nil, do: :index, else: :search

    fetched_rows = maybe_fetch_rows(rows, module, preloads, page, page_size)

    fetched_rows =
      Enum.map(
        fetched_rows,
        &GenericAdmin.call_module_function_or_default(admin_module, :before_filter, [&1], &1)
      )

    assocs =
      Enum.map(fetched_rows, fn row ->
        {row.id, SanbaseWeb.GenericAdminController.LinkBuilder.build_link(module, row)}
      end)
      |> Map.new()

    %{
      rows: fetched_rows,
      rows_count: total_count,
      current_page: page,
      page_size: page_size,
      action: action,
      assocs: assocs,
      search: params[:search]
    }
    |> Map.merge(resource_params(conn, resource, action))
  end

  defp maybe_fetch_rows(rows, module, preloads, page, page_size) do
    offset = page * page_size

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
  end

  defp resource_params(%Plug.Conn{} = conn, resource, action, params \\ %{}) do
    resource_config = resource_module_map(conn)[resource]
    resource_name = String.capitalize(resource)
    module = resource_config[:module]

    fields_override = resource_config[:fields_override] || %{}
    field_type_map = field_type_map(module, fields_override)
    extra_fields = Map.keys(fields_override)
    funcs = field_key_map(fields_override, :value_modifier)
    collections = field_key_map(fields_override, :collection)
    belongs_to_fields = resource_config[:belongs_to_fields] || %{}
    belongs_to_fields = transform_belongs_to(belongs_to_fields, params)

    fields = determine_fields(action, resource_config, module, extra_fields)

    %{
      resource: resource,
      resource_name: resource_name,
      fields: fields,
      funcs: funcs,
      actions: resource_config[:actions],
      field_type_map: field_type_map,
      search_fields: fields(module, extra_fields),
      collections: collections,
      belongs_to_fields: belongs_to_fields,
      custom_index_actions: resource_config[:custom_index_actions]
    }
  end

  defp determine_fields(action, resource_config, module, extra_fields) do
    case action do
      action when action in [:index, :search] ->
        determine_index_fields(resource_config, module, extra_fields)

      :show ->
        fields(module, extra_fields)

      action when action in [:new, :create] ->
        resource_config[:new_fields] || []

      action when action in [:edit, :update] ->
        resource_config[:edit_fields] || []

      _ ->
        fields(module, extra_fields)
    end
  end

  defp determine_index_fields(resource_config, module, extra_fields) do
    case resource_config[:index_fields] do
      nil -> fields(module, extra_fields)
      :all -> fields(module, extra_fields)
      fields when is_list(fields) -> fields
    end
  end

  defp field_key_map(fields_override, key) do
    fields_override
    |> Map.filter(fn {_field, data} -> Map.has_key?(data, key) end)
    |> Enum.map(fn {field, data} -> {field, Map.get(data, key)} end)
    |> Enum.into(%{})
  end

  defp fields(module, extra_fields \\ []) do
    (module.__schema__(:fields) ++ extra_fields) |> Enum.uniq()
  end

  defp field_type_map(module, fields_override) do
    field_type_map = field_type_map(module)

    fields_override =
      fields_override
      |> Enum.filter(fn {_field, data} -> Map.has_key?(data, :type) end)
      |> Enum.map(fn {field, data} -> {field, data.type} end)
      |> Enum.into(%{})

    Map.merge(field_type_map, fields_override)
  end

  defp field_type_map(module) do
    fields(module)
    |> Enum.map(&{&1, module.__schema__(:type, &1)})
    |> Enum.into(%{})
  end

  defp transform_belongs_to(belongs_to_fields, params) do
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

  defp build_field_condition(field, value, module) do
    field = String.to_existing_atom(field)
    value = String.trim(value)
    field_type = module.__schema__(:type, field)

    # Get the source field definition from the schema
    field_source = module.__schema__(:field_source, field)
    table = module.__schema__(:source)

    # Query to get the column type from PostgreSQL's information schema
    [data_type, _udt_name] =
      Sanbase.Repo.query!(
        """
        SELECT data_type, udt_name
        FROM information_schema.columns
        WHERE table_name = $1 AND column_name = $2
        """,
        [table, to_string(field_source || field)]
      )
      |> Map.get(:rows)
      |> List.first()

    cond do
      # Check if it's a custom enum type
      # Oban jobs' state return :string ecto type but underneath is a custom enum type
      data_type == "USER-DEFINED" ->
        dynamic([m], field(m, ^field) == ^value)

      field_type == :string ->
        value = "%" <> value <> "%"
        dynamic([m], ilike(field(m, ^field), ^value))

      true ->
        dynamic([m], field(m, ^field) == ^value)
    end
  end

  defp sort_field(module) do
    fields = fields(module)

    cond do
      :id in fields -> :id
      :inserted_at in fields -> :inserted_at
      true -> raise("Ecto schema module #{module} does not have :id or :inserted_at fields")
    end
  end

  defp to_integer(value) do
    case value do
      nil -> nil
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end
end

defmodule SanbaseWeb.GenericAdminController.LinkBuilder do
  def build_link(module, record) do
    module.__schema__(:associations)
    |> Enum.reduce(%{}, fn assoc_name, acc ->
      assoc_info = module.__schema__(:association, assoc_name)

      case assoc_info do
        %Ecto.Association.BelongsTo{related: related_module} ->
          {field, link} = link_belongs_to(record, related_module, assoc_name)
          Map.put(acc, field, link)

        _ ->
          acc
      end
    end)
  end

  defp link_belongs_to(record, related_module, assoc_name) do
    # credo:disable-for-next-line
    field_name = String.to_atom("#{assoc_name}_id")
    field_value = Map.get(record, field_name)

    if is_nil(field_value) do
      {to_string(assoc_name), nil}
    else
      resource = module_to_resource_name(related_module)
      link = href(resource, field_value, "#{field_name}: #{field_value}")
      {field_name, link}
    end
  end

  defp href(resource, id, label) do
    relative_url =
      SanbaseWeb.Router.Helpers.generic_admin_path(SanbaseWeb.Endpoint, :show, id,
        resource: resource
      )

    PhoenixHTMLHelpers.Link.link(label,
      to: relative_url,
      class: "text-blue-600 hover:text-blue-800"
    )
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
