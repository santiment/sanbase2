defmodule Sanbase.MapUtils do
  def drop_diff_keys(left, right) do
    Map.drop(left, Map.keys(left) -- Map.keys(right))
  end
end
