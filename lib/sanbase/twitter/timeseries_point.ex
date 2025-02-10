defmodule Sanbase.Twitter.TimeseriesPoint do
  @moduledoc false
  defstruct [
    :datetime,
    :twitter_handle,
    :followers_count
  ]

  def new(map) when is_map(map) do
    %__MODULE__{
      datetime: map.datetime,
      twitter_handle: map.twitter_handle,
      followers_count: map[:value] || map[:followers_count]
    }
  end

  def json_kv_tuple(%__MODULE__{} = point) do
    point =
      point
      |> Map.put(:timestamp, DateTime.to_unix(point.datetime))
      |> Map.delete(:datetime)
      |> Map.from_struct()

    key = Enum.join([point.twitter_handle, point.timestamp], "_")

    {key, Jason.encode!(point)}
  end
end
