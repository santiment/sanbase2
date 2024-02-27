defmodule Mix.Tasks.Gen.Admin.Resource do
  use Mix.Task

  @shortdoc "Generates an empty admin resource module."
  @moduledoc """
  Generates an empty admin resource module based on an Ecto schema module and a web root.

  ## Examples

    mix gen.admin.resource Sanbase.Ecosystem
  """

  def run([schema_module | _] = args) do
    # Determine the schema module and web root
    {web_root_dir, web_root_module} =
      case length(args) > 1 do
        true ->
          web_root_module = Enum.at(args, 1)
          {to_snake_case(web_root_module), web_root_module}

        false ->
          guess_web_root()
      end

    if schema_module in [nil, ""] or web_root_dir in [nil, ""] do
      Mix.shell().error("You must provide a schema module.")
    else
      schema_module = :"Elixir.#{schema_module}"
      content = generate_content(schema_module, web_root_module)

      schema_module_name = Module.split(schema_module) |> List.last()

      file_path =
        "lib/#{String.downcase(web_root_dir)}/generic_admin/#{String.downcase(schema_module_name)}.ex"

      File.write(file_path, content)
      Mix.shell().info("Generated #{file_path}")
    end
  end

  defp guess_web_root do
    "lib"
    |> File.ls!()
    |> Enum.map(&Path.join("lib", &1))
    |> Enum.filter(&File.dir?(&1))
    |> Enum.find(fn dir -> String.ends_with?(dir, "web") end)
    |> case do
      nil ->
        {nil, nil}

      web_root ->
        web_root = Path.basename(web_root)
        {web_root, to_camel_case(web_root)}
    end
  end

  defp to_camel_case(str) do
    str
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  defp to_snake_case(str) do
    str
    |> Macro.underscore()
  end

  defp generate_content(schema_module, web_root) do
    index_fields = get_index_fields(schema_module)
    preloads = get_preloads(schema_module)
    form_fields = form_fields(schema_module)

    """
    defmodule #{web_root}.GenericAdmin.#{Module.split(schema_module) |> List.last()} do
      def schema_module, do: #{schema_module}

      def resource() do
        %{
          actions: [:new, :edit],
          index_fields: #{inspect(index_fields)},
          new_fields: #{inspect(form_fields)},
          edit_fields: #{inspect(form_fields)},
          preloads: #{inspect(preloads)},
          belongs_to_fields: %{},
          field_types: %{},
          funcs: %{}
        }
      end
    end
    """
  end

  defp get_index_fields(schema_module) do
    schema_module.__schema__(:fields)
  end

  def form_fields(schema_module) do
    schema_module.__schema__(:fields)
    |> Enum.reject(fn field -> field in [:id, :inserted_at, :updated_at] end)
  end

  defp get_preloads(schema_module) do
    schema_module.__schema__(:associations)
    |> Enum.map(&{&1, schema_module.__schema__(:association, &1)})
    |> Enum.filter(fn {_assoc_name, assoc} -> assoc.related != nil end)
    |> Enum.map(fn {assoc_name, _assoc} -> assoc_name end)
  end
end
