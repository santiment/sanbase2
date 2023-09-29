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

    iex> Sanbase.TemplateEngine.run("Human Readable MediumNum: {{medium_num:human_readable}}", %{medium_num: 100000})
    "Human Readable MediumNum: 100,000.00"

    iex> Sanbase.TemplateEngine.run("BigNum: {{big_num}}", %{big_num: 999999999999})
    "BigNum: 999999999999"

    iex> Sanbase.TemplateEngine.run("Human Readable BigNum: {{big_num:human_readable}}", %{big_num: 999999999999})
    "Human Readable BigNum: 1,000.00 Billion"

    iex> Sanbase.TemplateEngine.run("{{timebound}} has human readable value {{timebound:human_readable}}", %{timebound: "3d"})
    "3d has human readable value 3 days"
  """

  defmodule TemplateEngineException do
    defexception [:message]
  end

  @template_regex ~r/\{\{(?<capture>.*?)\}\}/

  @spec run(String.t(), map) :: String.t()
  def run(template, params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
    env = Sanbase.Clickhouse.Query.Environment.empty()

    captures = Regex.scan(@template_regex, template, capture: :all_but_first)

    captures
    |> Enum.reduce(template, fn [key], template_acc ->
      case prepare_replace(template_acc, key, env, params) do
        {key, {:ok, value}} ->
          String.replace(template_acc, "{{#{key}}}", to_string(value))

        {_key, :no_value} ->
          template_acc
      end
    end)
  end

  @spec run_generate_positional_params(String.t(), map(), map()) :: {String.t(), list(any())}
  def run_generate_positional_params(template, params, env) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)

    captures =
      Regex.scan(@template_regex, template, capture: :all_but_first)
      |> Enum.uniq()

    {sql, args, _position} =
      captures
      |> Enum.reduce(
        {template, _args = [], _position = 1},
        fn [key], {template_acc, args_acc, position} ->
          case prepare_replace(template, key, env, params) do
            {_key, {:ok, value}} ->
              template_acc = String.replace(template_acc, "{{#{key}}}", "?#{position}")

              args_acc = [value | args_acc]

              {template_acc, args_acc, position + 1}

            {_key, :no_value} ->
              raise(TemplateEngineException,
                message: """
                Error generating positional parameters. The key '#{key}' has no value
                in the parameters map or the environment. Please check for typos,
                missing keys, inproper use of the environment variables or functions.

                Parameters: #{inspect(params)}
                Environment: #{inspect(env)}
                """
              )
          end
        end
      )

    {sql, Enum.reverse(args)}
  end

  defp prepare_replace(string, key, env, params) do
    value_tuple =
      cond do
        String.starts_with?(string, "@") ->
          "@" <> env_spec = key
          env_key = String.split(env_spec, "[", parts: 2) |> List.first()
          value = Map.get(env, env_key)

          # Apply the ["key"] part of the key
          {:ok, value}

        String.ends_with?(key, ":human_readable") ->
          [key, _] = String.split(key, ":human_readable")

          if not Map.has_key?(params, key),
            do: raise("Template parameter #{key} not found in the parameters map")

          value = params[key] |> human_readable()
          {:ok, value}

        Map.has_key?(params, key) ->
          value = params[key]
          {:ok, value}

        true ->
          :no_value
      end

    {key, value_tuple}
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
        raise(TemplateEngineException,
          message: """
          Error transforming #{inspect(data)} of type #{Sanbase.Utils.get_type(data)} into a human readable format.
          The value's type is not supported. The supported types are: DateTime, integers, floats and strings
          that represent intervals (1d, 5w, 12h, etc.)
          """
        )
    end
  end
end
