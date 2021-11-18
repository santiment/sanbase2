defmodule Sanbase.Clickhouse.Github.MetricAdapter.BrokenData do
  @json_file "broken_data.json"
  @external_resource json_file = Path.join(__DIR__, @json_file)

  _force_atoms_existence = [:why, :what, :notes, :actions_to_fix, :from, :to]

  @broken_data File.read!(json_file)
               |> Jason.decode!()
               |> Sanbase.MapUtils.atomize_keys()
               |> Enum.map(fn elem ->
                 elem
                 |> Map.put(:from, Sanbase.DateTimeUtils.from_iso8601!(elem[:from]))
                 |> Map.put(:to, Sanbase.DateTimeUtils.from_iso8601!(elem[:to]))
               end)

  def get(_metric, _slug, from, to) do
    [x1, x2] = [from, to] |> Enum.map(&DateTime.to_unix/1)

    # Return all the elements from the broken data list whose from-to range
    # overlaps in any way with the requested range.
    result =
      Enum.filter(@broken_data, fn elem ->
        [y1, y2] = [elem[:from], elem[:to]] |> Enum.map(&DateTime.to_unix/1)
        Enum.max([x1, y1]) <= Enum.min([x2, y2])
      end)

    {:ok, result}
  end
end
