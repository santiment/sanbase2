defmodule Sanbase.Billing.Plan.AccessMap do
  @moduledoc ~s"""
  Interprets an "access map" - the allow-list shape used by both custom plans and
  bundles to say which metrics, queries or signals a plan may use.

      %{
        "accessible" => ["price_usd", "active_addresses_24h"] | "all",
        "accessible_patterns" => ["^social_"],
        "not_accessible" => ["mvrv_usd"] | "all",
        "not_accessible_patterns" => ["_change_"]
      }

  Every key is optional. `accessible` defaults to `[]`, which allows nothing, so
  a map that is empty or `nil` grants no access at all - the safe direction for
  an allow-list.

  `not_accessible` always wins over `accessible`.

  This logic was previously private to `CustomPlan.Loader`. It is extracted
  unchanged so the bundle path can reuse it rather than growing a second,
  subtly-different copy of the same rules. `Loader` now delegates here.

  ## Two ways to ask

  `resolve/2` returns the full list of allowed items. It walks every known metric
  (~1000) and compiles the patterns, so it is only worth calling when the whole
  list is genuinely wanted - listing what a plan offers, for instance.

  `allows?/2` answers for a single item without building the list. Access checks
  run on every request and ask about exactly one item, so they use this.
  """

  @type access_map :: map() | nil
  @type item :: String.t()

  @doc ~s"""
  All items the access map allows, given a function returning every known item.
  """
  @spec resolve(access_map(), (-> [item()])) :: [item()]
  def resolve(access_map, get_all_items) do
    access_map = access_map || %{}

    accessible = Map.get(access_map, "accessible", [])
    accessible_patterns = Map.get(access_map, "accessible_patterns", [])
    not_accessible = Map.get(access_map, "not_accessible", [])
    not_accessible_patterns = Map.get(access_map, "not_accessible_patterns", [])

    all_items = get_all_items.()

    # Step 1: Build the accessible list from explicit items + pattern matches
    accessible_list =
      case accessible do
        "all" ->
          all_items

        list when is_list(list) ->
          accessible_by_pattern = matching_by_patterns(all_items, accessible_patterns)
          Enum.uniq(list ++ accessible_by_pattern)
      end

    # Step 2: Remove not_accessible items (not_accessible has HIGHER priority)
    not_accessible_list =
      case not_accessible do
        "all" -> all_items
        list when is_list(list) -> list
      end

    not_accessible_by_pattern = matching_by_patterns(accessible_list, not_accessible_patterns)

    accessible_list -- (not_accessible_list ++ not_accessible_by_pattern)
  end

  @doc ~s"""
  Whether the access map allows a single item.

  Equivalent to `item in resolve(access_map, get_all_items)` for any item that
  exists, but without enumerating anything.

  One deliberate difference: `resolve/2` matches `accessible_patterns` against
  the list of known items, so a pattern can only ever grant access to something
  real. Here there is no such list, so a **non-existent** name that matches an
  accessible pattern is reported as allowed. That is harmless - the request then
  fails further along because the metric does not exist - and it is the reason
  this function is not used to build lists.
  """
  @spec allows?(access_map(), item()) :: boolean()
  def allows?(access_map, item) when is_binary(item) do
    access_map = access_map || %{}

    allowed? =
      accessible?(Map.get(access_map, "accessible", []), item) or
        matches_any_pattern?(item, Map.get(access_map, "accessible_patterns", []))

    denied? =
      accessible?(Map.get(access_map, "not_accessible", []), item) or
        matches_any_pattern?(item, Map.get(access_map, "not_accessible_patterns", []))

    allowed? and not denied?
  end

  defp accessible?("all", _item), do: true
  defp accessible?(list, item) when is_list(list), do: item in list
  defp accessible?(_, _item), do: false

  defp matches_any_pattern?(_item, []), do: false

  defp matches_any_pattern?(item, patterns) when is_list(patterns) do
    Enum.any?(patterns, fn pattern -> String.match?(item, Regex.compile!(pattern)) end)
  end

  defp matches_any_pattern?(_item, _patterns), do: false

  # From the given list, return those items that match at least one of the
  # provided regex patterns.
  # Example: pattern "mvrv_" matches all MVRV metrics; pattern "^social_"
  # matches all metrics starting with "social_".
  defp matching_by_patterns(_list, []), do: []

  defp matching_by_patterns(list, patterns) do
    regex_list = Enum.map(patterns, &Regex.compile!/1)

    Enum.filter(list, fn elem ->
      Enum.any?(regex_list, fn regex -> String.match?(elem, regex) end)
    end)
  end
end
