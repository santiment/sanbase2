defmodule Sanbase.Etherbi.Utils do
  @doc ~S"""
    If the difference between the datetimes is too large the query will be too big
    Allow the max difference between the datetimes to be 1 month by default. You can
    override this by passing a third parameter in seconds
  """
  @spec calculate_to_datetime(%DateTime{}, %DateTime{}) :: %DateTime{}
  def calculate_to_datetime(from_datetime, to_datetime, limit_sec \\ 60 * 60 * 24) do
    if DateTime.diff(to_datetime, from_datetime, :seconds) > limit_sec do
      Sanbase.DateTimeUtils.seconds_after(limit_sec, from_datetime)
    else
      to_datetime
    end
  end
end