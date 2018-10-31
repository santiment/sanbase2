defmodule Mix.Tasks.GenClickhouseMigration do
  use Mix.Task

  import Macro, only: [underscore: 1]
  import Mix.Generator

  @shortdoc "Generates an empty clickhouse migration"

  @moduledoc """
  Generates an empty clickhouse migration file.
  """

  def run(args) do
    [name] = args
    file = "db/#{timestamp()}_#{underscore(name)}.sql"
    create_file(file, "")
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)
end
