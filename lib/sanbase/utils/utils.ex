defmodule Sanbase.Utils do
  @moduledoc false
  alias Sanbase.Utils.Config

  @doc ~s"""
  Get the name of the type of a value
  """
  @spec get_type(any()) :: atom()
  def get_type(value) do
    cond do
      is_binary(value) -> :binary
      is_bitstring(value) -> :bitstring
      is_atom(value) -> :atom
      is_pid(value) -> :pid
      is_boolean(value) -> :boolean
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_number(value) -> :number
      is_list(value) -> :list
      is_struct(value) -> :struct
      is_map(value) -> :map
      is_tuple(value) -> :tuple
      is_port(value) -> :port
      is_reference(value) -> :reference
      true -> raise("Unknown type #{inspect(value)}")
    end
  end

  @prod_db_patterns ["amazonaws"]
  def prod_db? do
    database_url = System.get_env("DATABASE_URL")

    database_hostname = Config.module_get(Sanbase.Repo, :hostname)

    prod_db_url? =
      not is_nil(database_url) and
        Enum.any?(@prod_db_patterns, &String.contains?(database_url, &1))

    prod_db_config? =
      not is_nil(database_hostname) and
        Enum.any?(@prod_db_patterns, &String.contains?(database_hostname, &1))

    prod_db_url? or prod_db_config?
  end
end
