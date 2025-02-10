defmodule Sanbase.Dashboard.Database.Table do
  @moduledoc ~s"""
  List the tables to which the SQL Editor has access to.

  The list of tables can be obtained from two places:
  - A file stored in this repository called `tables.json`
  - A file mounted by Kubernetes that can be reloaded from the devops repo
    without the need to change, compile and deploy the backend
  """

  require Sanbase.Utils.Config, as: Config

  @json_file "tables.json"
  @external_resource json_file = Path.join(__DIR__, @json_file)

  @tables json_file |> File.read!() |> Jason.decode!(strict: true, keys: :atoms)

  @typedoc ~s"""
  The columns are represented as a map where the column name is the key
  and the column type is the value.
  Example: %{slug: "LowCardinality(String)", dt: "DateTime"}
  """
  @type columns_map :: %{required(Atom.t()) => String.t()}

  @type t :: %{
          table: Striong.t(),
          columns: columns_map(),
          description: String.t(),
          engine: String.t(),
          order_by: list(String.t()),
          partition_by: String.t()
        }

  @doc ~s"""
  Get the list of Clickhouse tables available in the SQL Editor.

  Every table is described as map and contains information about the
  columns, partitioning, ordering and engine used.
  """
  @spec get_tables() :: {:ok, list(t())} | {:error, String.t()}
  def get_tables do
    case tables_source() do
      "local_file" -> get_tables_local_file()
      "mounted_file" -> get_tables_mounted_file()
    end
  end

  # Private functions

  defp tables_source, do: Config.module_get(Sanbase.Dashboard, :tables_source, "local_file")

  defp get_tables_local_file, do: {:ok, @tables}

  defp get_tables_mounted_file do
    path = Config.module_get(Sanbase.Dashboard, :mounted_file_path)

    case File.read(path) do
      # credo:disable-for-next-line
      {:ok, contents} -> Jason.decode!(contents, strict: true, keys: :atoms)
      {:error, :enoent} -> {:error, "Tables file does not exist in the mounted file location"}
    end
  end
end
