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
    try do
      apply(module, function, data)
    rescue
      UndefinedFunctionError -> default_value
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
end
