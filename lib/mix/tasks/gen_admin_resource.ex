defmodule Mix.Tasks.Gen.Admin.Resource do
  @shortdoc "Generates an empty admin resource module."
  @moduledoc """
  Generates an empty admin resource module based on an Ecto schema module and a web root.

  ## Examples

  mix gen.admin.resource Sanbase.Ecosystem
  """

  use Mix.Task

  def run([schema_module | _] = args) do
    {web_root_dir, web_root_module} =
      if length(args) > 1 do
        web_root_module = Enum.at(args, 1)
        {Macro.underscore(web_root_module), web_root_module}
      else
        guess_web_root()
      end

    if schema_module in [nil, ""] or web_root_dir in [nil, ""] do
      Mix.shell().error("You must provide a schema module.")
    else
      schema_module = Module.safe_concat([schema_module])
      content = generate_content(schema_module, web_root_module)

      schema_module_name = schema_module |> Module.split() |> List.last()

      file_path =
        "lib/#{String.downcase(web_root_dir)}/generic_admin/#{Macro.underscore(schema_module_name)}.ex"

      if File.exists?(file_path) do
        IO.puts("#{file_path} already exists.")
        IO.puts("Do you want to overwrite it? [Yn]")

        case IO.gets("> ") do
          "Y\n" ->
            File.write!(file_path, content)
            Mix.shell().info("Overwritten #{file_path}")

          _ ->
            Mix.shell().info("Skipped #{file_path}")
        end
      else
        File.write!(file_path, content)
        Mix.shell().info("Generated #{file_path}")
      end
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
        {web_root, Macro.camelize(web_root)}
    end
  end

  defp generate_content(schema_module, web_root) do
    index_fields = get_index_fields(schema_module)
    preloads = get_preloads(schema_module)
    belongs_to_fields = belongs_to_fields(schema_module)
    form_fields = form_fields(schema_module, belongs_to_fields)
    belongs_to_fields_map = generate_belongs_to_fields_map(schema_module)

    """
    defmodule #{web_root}.GenericAdmin.#{schema_module |> Module.split() |> List.last()} do
      def schema_module, do: #{schema_module |> to_string() |> String.replace_prefix("Elixir.", "")}

      def resource() do
        %{
          actions: [:new, :edit],
          index_fields: #{inspect(index_fields)},
          new_fields: #{inspect(form_fields)},
          edit_fields: #{inspect(form_fields)},
          preloads: #{inspect(preloads)},
          belongs_to_fields: #{inspect(belongs_to_fields_map, pretty: true)}, #{if length(belongs_to_fields) > 0, do: "#TODO fill search_fields list with fields from the belongs_to resource", else: ""}
          fields_override: %{}
        }
      end
    end
    """
  end

  defp belongs_to_fields(schema_module) do
    :associations
    |> schema_module.__schema__()
    |> Enum.filter(fn assoc_name ->
      assoc = schema_module.__schema__(:association, assoc_name)
      assoc.__struct__ == Ecto.Association.BelongsTo
    end)
  end

  defp generate_belongs_to_fields_map(schema_module) do
    schema_module
    |> belongs_to_fields()
    |> Map.new(fn assoc_name ->
      {
        assoc_name,
        %{
          resource:
            assoc_name
            |> to_string()
            |> Macro.underscore()
            |> Inflex.pluralize(),
          # TODO: add search fields from the associated module
          search_fields: []
        }
      }
    end)
  end

  defp get_index_fields(schema_module) do
    schema_module.__schema__(:fields)
  end

  def form_fields(schema_module, preloads) do
    :fields
    |> schema_module.__schema__()
    |> Enum.reject(fn field ->
      field in [:id, :inserted_at, :updated_at] or
        maybe_replace_foreign_key(field) in preloads
    end)
    |> Enum.concat(preloads)
    |> Enum.uniq()
  end

  defp maybe_replace_foreign_key(field) do
    field
    |> to_string()
    |> String.replace_suffix("_id", "")
    |> String.to_existing_atom()
  end

  defp get_preloads(schema_module) do
    :associations
    |> schema_module.__schema__()
    |> Enum.map(&{&1, schema_module.__schema__(:association, &1)})
    |> Enum.filter(fn {_assoc_name, assoc} -> assoc.related != nil end)
    |> Enum.map(fn {assoc_name, _assoc} -> assoc_name end)
  end
end
