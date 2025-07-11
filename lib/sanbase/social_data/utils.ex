defmodule Sanbase.SocialData.Utils do
  def maybe_add_and_rename_field(map, selector, key, as_key) when is_map(map) do
    if value = Map.get(selector, key) do
      Map.put(map, as_key, value)
    else
      map
    end
  end

  def maybe_add_and_rename_field(list, selector, key, as_key) when is_list(list) do
    if value = Map.get(selector, key) do
      [{as_key, value}] ++ list
    else
      list
    end
  end
end
