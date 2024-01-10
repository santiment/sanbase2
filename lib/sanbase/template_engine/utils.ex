defmodule Sanbase.TemplateEngine.Utils do
  def stringify_value(value) do
    cond do
      is_number(value) -> to_string(value)
      is_binary(value) -> value
      is_boolean(value) -> to_string(value)
      is_list(value) -> inspect(value)
      is_map(value) -> Jason.encode!(value)
      is_atom(value) -> to_string(value)
      true -> raise("Unsupported value type for value: #{inspect(value)}")
    end
  end

  # Numbers below 1000 are not changed
  # Numbers between 1000 and 1000000 are delimited: 999,523.00, 123,529.12
  # Number bigger than 1000000 are made human readable: 1.54 Million, 85.00 Billion
  defguard is_number_outside_range_inclusive(num, low, high)
           when is_number(num) and (num >= high or num <= low)

  defguard is_number_inside_range_exclusive(num, low, high)
           when is_number(num) and (num > low and num < high)

  def human_readable(data) do
    cond do
      # Transform interval to human readable interval
      Sanbase.DateTimeUtils.valid_interval?(data) ->
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

      true ->
        raise(Sanbase.TemplateEngine.TemplateEngineException,
          message: """
          Error transforming #{inspect(data)} of type #{Sanbase.Utils.get_type(data)} into a human readable format.
          The value's type is not supported. The supported types are: DateTime, integers, floats and strings
          that represent intervals (1d, 5w, 12h, etc.)
          """
        )
    end
  end
end
