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

  def resource_module_map do
    Enum.reduce(custom_defined_modules(), %{}, fn admin_module, acc ->
      Map.merge(acc, generate_resource(admin_module))
    end)
  end

  def generate_resource(admin_module) do
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
        |> Map.update(:actions, [], fn actions -> ([:show] ++ actions) |> Enum.uniq() end)
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
