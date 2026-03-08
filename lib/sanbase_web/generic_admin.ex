defmodule SanbaseWeb.GenericAdmin do
  def custom_defined_modules() do
    case :application.get_key(:sanbase, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.filter(fn module ->
          String.starts_with?(Atom.to_string(module), "Elixir.SanbaseWeb.GenericAdmin.")
        end)

      _ ->
        []
    end
  end

  def resource_module_map(%Plug.Conn{} = conn \\ %Plug.Conn{}) do
    Enum.reduce(custom_defined_modules(), %{}, fn admin_module, acc ->
      Map.merge(acc, generate_resource(conn, admin_module))
    end)
  end

  defp generate_resource(conn, admin_module) when is_atom(admin_module) do
    schema_module = admin_module.schema_module()

    resource_name =
      call_module_function_or_default(
        admin_module,
        :resource_name,
        [],
        schema_to_resource_name(schema_module)
      )

    %{
      resource_name =>
        %{
          module: schema_module,
          admin_module: admin_module,
          singular: Inflex.singularize(resource_name),
          actions: [],
          index_fields: :all,
          new_fields: [],
          edit_fields: [],
          funcs: %{}
        }
        |> Map.merge(call_module_function_or_default(admin_module, :resource, [], %{}))
        |> Map.update(:actions, [], fn actions ->
          actions = ([:show] ++ actions) |> Enum.uniq()

          if actions -- [:show, :new, :edit, :delete] != [],
            do:
              raise(ArgumentError,
                message:
                  "Unexpected action(s) in GenericAdmin: #{Enum.join(actions -- [:show, :edit, :delete], ", ")}"
              )

          # In some cases (like searching) we only want to get the resources and won't care about the
          # action buttons. In these cases `conn` will not be passed and the default empty conn will be
          # provided. Treat this as no roles
          roles = conn.assigns[:current_user_role_names] || []

          can_fn = fn action -> Sanbase.Admin.Permissions.can?(action, roles: roles) end

          actions
          |> then(fn l -> if can_fn.(:new), do: l, else: l -- [:new] end)
          |> then(fn l -> if can_fn.(:edit), do: l, else: l -- [:edit] end)
          |> then(fn l -> if can_fn.(:delete), do: l, else: l -- [:delete] end)
        end)
    }
  end

  def resources do
    custom_defined_modules()
    |> Enum.map(&schema_to_resource_name/1)
  end

  def call_module_function_or_default(module, function, data, default_value) do
    if function_exported?(module, function, length(data)) do
      apply(module, function, data)
    else
      default_value
    end
  end

  def schema_to_resource_name(schema_module) do
    schema_module
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> Inflex.underscore()
    |> Inflex.pluralize()
  end

  # ---------------------------------------------------------------------------
  # Shared helpers for resource modules
  # ---------------------------------------------------------------------------

  @doc """
  Generates an HTML link to a GenericAdmin show page for a given resource.
  Used by resource modules to create clickable links in value_modifier functions.
  """
  def resource_link(resource, id, label) do
    relative_url =
      SanbaseWeb.Router.Helpers.generic_admin_path(SanbaseWeb.Endpoint, :show, id,
        resource: resource
      )

    PhoenixHTMLHelpers.Link.link(label,
      to: relative_url,
      class: "text-blue-600 hover:text-blue-800"
    )
  end

  @doc """
  Common belongs_to definition for Project associations.
  Used by many resource modules that have a project_id foreign key.
  """
  def belongs_to_project do
    import Ecto.Query, only: [from: 2], warn: false

    %{
      query: from(p in Sanbase.Project, order_by: p.id),
      transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
      resource: "projects",
      search_fields: [:name, :slug, :ticker]
    }
  end

  @doc """
  Common belongs_to definition for User associations.
  Used by resource modules that have a user_id foreign key.
  """
  def belongs_to_user do
    import Ecto.Query, only: [from: 2], warn: false

    %{
      query: from(u in Sanbase.Accounts.User, order_by: [desc: u.id]),
      transform: fn rows -> Enum.map(rows, &{&1.email, &1.id}) end,
      resource: "users",
      search_fields: [:email, :username]
    }
  end
end
