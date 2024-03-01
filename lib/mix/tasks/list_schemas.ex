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
      |> Enum.filter(fn module -> to_string(module) =~ ~r/^Elixir\.Sanbase/ end)
      |> Enum.filter(&({:__schema__, 1} in &1.__info__(:functions)))

    schema_modules_with_admin =
      SanbaseWeb.GenericAdmin.resource_module_map()
      |> Enum.map(fn {_, %{module: module}} -> module end)

    IO.puts("Schema modules without admin:")

    modules
    |> Enum.reject(fn module -> module in schema_modules_with_admin end)
    |> Enum.each(&IO.inspect(&1))
  end
end
