defmodule Sanbase.Twitter.TimeseriesPoint do
  defstruct [
    :slug,
    :datetime,
    :value
  ]

  def new(map) when is_map(map) do
    %__MODULE__{
      slug: map.slug,
      datetime: map.datetime,
      value: map.value
    }
  end

  def json_kv_tuple(%__MODULE__{} = point) do
    point =
      point
      |> Map.put(:timestamp, DateTime.to_unix(point.datetime))
      |> Map.delete(:datetime)
      |> Map.from_struct()

    key =
      [point.slug, point.value, point.timestamp]
      |> Enum.join("_")

    {key, Jason.encode!(point)}
  end
end
