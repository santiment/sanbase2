defmodule Sanbase.Dashboard.Database.Table do
  @json_file "tables.json"
  @external_resource json_file = Path.join(__DIR__, @json_file)

  @tables File.read!(json_file) |> Jason.decode!(strict: true, keys: :atoms)

  def get_tables(), do: @tables
end
