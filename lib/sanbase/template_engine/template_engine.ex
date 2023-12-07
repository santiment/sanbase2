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
    # k(ey) is either atom or string
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
    env = Sanbase.Clickhouse.Query.Environment.empty()

    get_captures(template)
    |> Enum.reduce(template, fn
      %{code?: false} = map, template_acc ->
        replace_template_key_with_value(template_acc, map, params, env)

      %{code?: true} = map, template_acc ->
        replace_template_key_with_code_execution(template_acc, map, env)
    end)
  end

  defp replace_template_key_with_value(template, %{key: key, content: content}, params, env) do
    case prepare_replace(template, content, params, env) do
      {:ok, value} -> String.replace(template, key, stringify_value(value))
      :no_value -> template
    end
  end

  defp replace_template_key_with_code_execution(
         template,
         %{lang: "san", lang_version: "1.0"} = map,
         env
       ) do
    execution_result = Sanbase.SanLang.eval(map.content, env)
    String.replace(template, map.key, stringify_value(execution_result))
  end

  defp stringify_value(value) do
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

  @spec run_generate_positional_params(String.t(), map(), map()) :: {String.t(), list(any())}
  def run_generate_positional_params(template, params, env) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
    captures = get_captures(template)

    {sql, args, _position} =
      Enum.reduce(
        captures,
        {template, _args = [], _position = 1},
        fn %{code?: false} = map, {template_acc, args_acc, position} ->
          case prepare_replace(template, map.content, params, env) do
            {:ok, value} ->
              template_acc = String.replace(template_acc, map.key, "?#{position}")
              args_acc = [value | args_acc]
              {template_acc, args_acc, position + 1}

            :no_value ->
              raise_positional_params_error(template, map.content, params, env)
          end
        end
      )

    {sql, Enum.reverse(args)}
  end

  defp raise_positional_params_error(template, key, params, env) do
    raise(TemplateEngineException,
      message: """
      Error parsing the template. The template contains a key that is not present in the params map.

      Template: #{inspect(template)}
      Key: #{inspect(key)}
      Params: #{inspect(params)}
      Env: #{inspect(env)}
      """
    )
  end

  @doc ~s"""
  Extract the captures from the template. The captures are the keys that are enclosed in {{}}
  """
  def get_captures(template) do
    captures =
      Regex.scan(@template_regex, template)
      |> Enum.uniq()
      |> Enum.map(fn [key_with_enclosing_curly_braces, inner] ->
        inner = String.trim(inner)
        content_data_map = parse_template_inner(inner)
        # The template itself is needed in order to find/replace it with the value.
        content_data_map
        |> Map.put(:key, key_with_enclosing_curly_braces)
      end)

    if Enum.any?(captures, fn map -> String.contains?(map.content, ["{", "}"]) end) do
      raise(TemplateEngineException,
        message: """
        Error parsing the template. The template contains a key that itself contains
        { or }. This means that an opening or closing bracket is missing.

        Template: #{inspect(template)}
        """
      )
    end

    captures
  end

  defp parse_template_inner("[lang=" <> rest) do
    [lang_with_version, rest] = String.split(rest, "]", parts: 2)
    [lang, version] = String.split(lang_with_version, ":")

    %{
      code?: true,
      lang: String.trim(lang),
      lang_version: String.trim(version),
      content: String.trim(rest)
    }
  end

  defp parse_template_inner(content) do
    %{code?: false, lang: nil, lang_version: nil, content: String.trim(content)}
  end

  defp prepare_replace(string, key, params, env) do
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
