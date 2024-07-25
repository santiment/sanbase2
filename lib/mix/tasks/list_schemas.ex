defmodule Mix.Tasks.List.Schema.Modules.Without.Admin do
  use Mix.Task

  @moduledoc """
  Lists all Ecto schema modules without an admin module.
  Usage:

  mix list.schema.modules.without.admin
  """

  def run(_) do
    {:ok, modules} = :application.get_key(:sanbase, :modules)

    modules =
      modules
      |> Enum.filter(fn module ->
        sanbase_module? = String.starts_with?(to_string(module), "Elixir.Sanbase")

        schema_module? =
          function_exported?(module, :__info__, 1) and
            {:__schema__, 1} in module.__info__(:functions)

        sanbase_module? and schema_module?
      end)

    schema_modules_with_admin =
      SanbaseWeb.GenericAdmin.resource_module_map()
      |> Enum.map(fn {_, %{module: module}} -> module end)

    IO.puts("Schema modules without admin:")

    modules
    |> Enum.reject(fn module -> module in schema_modules_with_admin end)
    |> Enum.each(&IO.puts(&1))
  end
end
