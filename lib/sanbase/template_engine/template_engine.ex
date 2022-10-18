defmodule Sanbase.TemplateEngine do
  @moduledoc ~s"""
  Produce a string value from a given template and key-value enumerable.
  All occurances in the template that are enclosed in double braces are replaced
  with the corersponding values from KV enumerable.

  There are two ways to transform a value into its human readable variant.

  The first way is to provide an :__human_readable__ key inside the kv argument which
  is a list of the keys that need to be transformed.

  The second way is to replace the `{{key}}` in the template with `{{key:human_readable}}`.
  This way is more flexible as it allows to make only enable transformation into
  human readable only for parts of the template.

  Example:
    iex> Sanbase.TemplateEngine.run("My name is {{name}}", %{name: "San"})
    "My name is San"

    iex> Sanbase.TemplateEngine.run("{{a}}{{b}}{{a}}{{a}}", %{a: "1", b: 2})
    "1211"

    iex> Sanbase.TemplateEngine.run("SmallNum: {{small_num}}", %{small_num: 100})
    "SmallNum: 100"

    iex> Sanbase.TemplateEngine.run("MediumNum: {{medium_num}}", %{medium_num: 100000})
    "MediumNum: 100000"

    iex> Sanbase.TemplateEngine.run("Human Readable MediumNum: {{medium_num}}", %{medium_num: 100000, __human_readable__: [:medium_num]})
    "Human Readable MediumNum: 100,000.00"

    iex> Sanbase.TemplateEngine.run("BigNum: {{big_num}}", %{big_num: 999999999999})
    "BigNum: 999999999999"

    iex> Sanbase.TemplateEngine.run("Human Readable BigNum: {{big_num}}", %{big_num: 999999999999, __human_readable__: [:big_num]})
    "Human Readable BigNum: 1,000.00 Billion"

    iex> Sanbase.TemplateEngine.run("{{timebound}} has human readable value {{timebound:human_readable}}", %{timebound: "3d"})
    "3d has human readable value 3 days"
  """

  @spec run(String.t(), map) :: String.t()
  def run(template, kv) do
    {human_readable_map, kv} = Map.split(kv, [:__human_readable__])

    human_readable_mapset =
      Map.get(human_readable_map, :__human_readable__, [])
      |> MapSet.new()

    Enum.reduce(kv, template, fn {key, value}, acc ->
      # Support `key:human_readable` to convert the value to human readable even
      # if it's not part of the :__human_readable))
      human_readalbe_key = "#{key}:human_readable"

      acc
      |> replace(key, value, human_readable_mapset)
      |> replace(human_readalbe_key, value, MapSet.put(human_readable_mapset, human_readalbe_key))
    end)
  end

  defp replace(string, key, value, human_readable_mapset) do
    String.replace(string, "{{#{key}}}", fn _ ->
      case key in human_readable_mapset do
        true -> value |> human_readable() |> to_string()
        false -> value |> to_string()
      end
    end)
  end

  # Numbers below 1000 are not changed
  # Numbers between 1000 and 1000000 are delimited: 999,523.00, 123,529.12
  # Number bigger than 1000000 are made human readable: 1.54 Million, 85.00 Billion
  defguard is_number_outside_range_inclusive(num, low, high)
           when is_number(num) and (num >= high or num <= low)

  defguard is_number_inside_range_exclusive(num, low, high)
           when is_number(num) and (num > low and num < high)

  defp human_readable(data) do
    cond do
      # Transform interval to human readable interval
      true == Sanbase.DateTimeUtils.valid_interval?(data) ->
        Sanbase.DateTimeUtils.interval_to_str(data)

      # Transform numbers to human readable number
      is_number_outside_range_inclusive(data, -1_000_000, 1_000_000) ->
        Number.Human.number_to_human(data)

      is_number_outside_range_inclusive(data, -1000, 1000) ->
        Number.Delimit.number_to_delimited(data)

      is_number_inside_range_exclusive(data, -1, 1) ->
        Number.Delimit.number_to_delimited(data, precision: 8)

      is_float(data) ->
        Number.Delimit.number_to_delimited(data, precision: 2)

      is_integer(data) ->
        Integer.to_string(data)
    end
  end
end
