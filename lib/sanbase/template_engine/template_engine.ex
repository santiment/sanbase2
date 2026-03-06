defmodule Sanbase.TemplateEngine do
  @moduledoc ~s"""
  Process templates containing {{<key>}} and {% <code> %} placeholders.
  """

  import Sanbase.TemplateEngine.Utils, only: [human_readable: 1, stringify_value: 1]
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.TemplateEngine
  alias Sanbase.TemplateEngine.CodeEvaluation

  @type option :: {:params, map()} | {:env, Sanbase.SanLang.Environment.t()}

  @typedoc ~s"""
  The TemplateEngine function can accept the following options:
    - params: A map of key-value pairs that will be used to replace the simple keys in the template.
      The simple keys are the onces that are in the format {{<param_name}}.
    - env: A SanLang environment that will be used to evaluate the code templates in the template.
  """
  @type opts :: [option()]

  @type template_inner_content_data :: %{
          code?: boolean,
          lang: String.t() | nil,
          lang_version: String.t() | nil,
          inner_content: String.t(),
          key: String.t()
        }

  defmodule TemplateEngineError do
    defexception [:message]
  end

  @doc ~s"""
  Run the template engine on the given template and replace all param templates with their value
  and code templates with the result of the execution of the code.

  For `opts` see the type documentation.

    Examples:
      iex> run("My name is {{name}}", params: %{name: "San"})
      {:ok, "My name is San"}

      iex> run("{{a}}{{b}}{{a}}{{a}}", params: %{a: "1", b: 2})
      {:ok, "1211"}

      iex> run("SmallNum: {{small_num}}", params: %{small_num: 100})
      {:ok, "SmallNum: 100"}

      iex> run("MediumNum: {{medium_num}}", params: %{medium_num: 100000})
      {:ok, "MediumNum: 100000"}

      iex> run("Human Readable MediumNum: {{medium_num:human_readable}}", params: %{medium_num: 100000})
      {:ok, "Human Readable MediumNum: 100,000.00"}

      iex> run("BigNum: {{big_num}}", params: %{big_num: 999999999999})
      {:ok, "BigNum: 999999999999"}

      iex> run("Human Readable BigNum: {{big_num:human_readable}}", params: %{big_num: 999999999999})
      {:ok, "Human Readable BigNum: 1,000.00 Billion"}

      iex> run("{{timebound}} has human readable value {{timebound:human_readable}}", params: %{timebound: "3d"})
      {:ok, "3d has human readable value 3 days"}

      iex> run("{% 1 + 2 * 3 + 10 %}")
      {:ok, "17"}
  """
  @spec run(String.t(), opts) :: {:ok, String.t()} | {:error, String.t()}
  def run(template, opts \\ []) do
    params = Keyword.get(opts, :params, %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    env = Keyword.get(opts, :env, Sanbase.SanLang.Environment.new())

    with {:ok, captures} <- TemplateEngine.Captures.extract_captures(template) do
      template =
        Enum.reduce(captures, template, fn
          %{code?: false} = map, template_acc ->
            replace_template_key_with_value(template_acc, map, params, env)

          %{code?: true} = map, template_acc ->
            replace_template_key_with_code_execution(template_acc, map, params, env)
        end)

      {:ok, template}
    end
  end

  @doc ~s"""
  Same as run/2, but raises on error
  """
  @spec run!(String.t(), opts) :: String.t() | no_return
  def run!(template, opts \\ []) do
    run(template, opts) |> to_bang()
  end

  @doc ~s"""
  Run the template engine and generate a new template and a list of positional params
  that can be used in Clickhouse queries.

  The templates are replaced not with the actual value, but with a typed placeholder
  like `{$0:Int64}`, `{$1:String}`, etc. which correspond to the position of the value
  in the list of positional params. The indexes start from 0.

  Supports:
  - `{{key:inline}}` — direct string substitution (no placeholder, validated for safety)
  - `{{key:UInt64}}` — explicit CH type override (any known CH type)
  - `{{key}}` — auto-inferred type from the Elixir value
  - `{% code %}` — code evaluation, auto-inferred type

    Examples:
      iex> run_generate_positional_params("My name is {{name}}", params: %{name: "San"})
      {:ok, {"My name is {$0:String}", ["San"]}}

      iex> run_generate_positional_params("{{name}} is {% 20 + 8 %} years old", params: %{name: "Tom"})
      {:ok, {"{$0:String} is {$1:Int64} years old", ["Tom", 28]}}

      iex> run_generate_positional_params("param name is reused {{name}} {{name}} is {% 20 + 8 %} years old {{name}}", params: %{name: "Tom"})
      {:ok, {"param name is reused {$0:String} {$0:String} is {$1:Int64} years old {$0:String}", ["Tom", 28]}}
  """
  @spec run_generate_positional_params(String.t(), opts) :: {String.t(), list(any())}
  def run_generate_positional_params(template, opts) do
    params = Keyword.get(opts, :params, %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    env = Keyword.get(opts, :env, Sanbase.SanLang.Environment.new())

    with {:ok, captures} <- TemplateEngine.Captures.extract_captures(template),
         {:ok, result} <- do_run_generate_positional_params(template, captures, params, env) do
      {:ok, result}
    end
  end

  # Private

  defp do_run_generate_positional_params(template, captures, params, env) do
    # key_positions tracks already-seen param keys to their position index
    # so the same {{key}} reused multiple times maps to the same {$N:Type}
    {sql, args, errors, _position, _key_positions} =
      Enum.reduce(
        captures,
        {template, _args = [], _errors = [], _position = 0, _key_positions = %{}},
        fn
          %{code?: false} = capture_map,
          {template_acc, args_acc, errors, position, key_positions} ->
            case get_value_with_type_info(capture_map.inner_content, params) do
              {:ok, value, :inline} ->
                inline_value = to_string(value)
                validate_inline_value!(inline_value, capture_map.key)
                template_acc = String.replace(template_acc, capture_map.key, inline_value)
                {template_acc, args_acc, errors, position, key_positions}

              {:ok, value, type_or_nil} ->
                # Extract the base key (without modifier) for deduplication
                base_key = extract_base_key(capture_map.inner_content)
                ch_type = resolve_ch_type(value, type_or_nil)

                case Map.get(key_positions, base_key) do
                  nil ->
                    # First occurrence of this key
                    placeholder = "{$#{position}:#{ch_type}}"
                    template_acc = String.replace(template_acc, capture_map.key, placeholder)
                    args_acc = [value | args_acc]
                    key_positions = Map.put(key_positions, base_key, {position, ch_type})
                    {template_acc, args_acc, errors, position + 1, key_positions}

                  {existing_position, existing_type} ->
                    if type_or_nil != nil and ch_type != existing_type do
                      # Later explicit type override wins: update all prior placeholders,
                      # the arg entry, and key_positions to use the new type.
                      old_placeholder = "{$#{existing_position}:#{existing_type}}"
                      new_placeholder = "{$#{existing_position}:#{ch_type}}"

                      template_acc =
                        String.replace(template_acc, old_placeholder, new_placeholder)

                      template_acc =
                        String.replace(template_acc, capture_map.key, new_placeholder)

                      reverse_index = length(args_acc) - 1 - existing_position
                      args_acc = List.replace_at(args_acc, reverse_index, value)

                      key_positions =
                        Map.put(key_positions, base_key, {existing_position, ch_type})

                      {template_acc, args_acc, errors, position, key_positions}
                    else
                      # Reuse the existing position and type
                      placeholder = "{$#{existing_position}:#{existing_type}}"
                      template_acc = String.replace(template_acc, capture_map.key, placeholder)
                      {template_acc, args_acc, errors, position, key_positions}
                    end
                end

              :no_value ->
                error = %{
                  error: :missing_parameter,
                  key: capture_map.key
                }

                errors = [error | errors]
                {template_acc, args_acc, errors, position, key_positions}
            end

          %{code?: true} = capture_map,
          {template_acc, args_acc, errors, position, key_positions} ->
            execution_result = CodeEvaluation.eval(capture_map, env)
            ch_type = resolve_ch_type(execution_result, nil)
            placeholder = "{$#{position}:#{ch_type}}"
            template_acc = String.replace(template_acc, capture_map.key, placeholder)
            args_acc = [execution_result | args_acc]
            {template_acc, args_acc, errors, position + 1, key_positions}
        end
      )

    case errors do
      [] ->
        {:ok, {sql, Enum.reverse(args)}}

      _ ->
        missing_keys = Enum.map(errors, & &1.key) |> Enum.join(", ")
        params_keys = Map.keys(params)
        params_keys = if params_keys == [], do: "none", else: Enum.join(params_keys, ", ")

        error_str =
          """
          One or more of the {{<key>}} templates in the query text do not correspond to any of the parameters.
          Template keys missing from the parameters: #{missing_keys}. Parameters' keys defined: #{params_keys}
          """

        {:error, error_str}
    end
  end

  defp extract_base_key(inner_content) do
    {key, _modifier} = split_key_modifier(inner_content)
    key
  end

  defp resolve_ch_type(value, nil) do
    Sanbase.Clickhouse.Type.infer(value) |> IO.iodata_to_binary()
  end

  defp resolve_ch_type(_value, type_override) when is_binary(type_override) do
    type_override
  end

  defp validate_inline_value!(value, key) do
    unless Regex.match?(~r/^[a-zA-Z0-9_.]+$/, value) do
      raise TemplateEngineError,
        message:
          "Inline value for #{key} contains invalid characters. " <>
            "Only alphanumeric characters, underscores, and dots are allowed. Got: #{value}"
    end
  end

  defp replace_template_key_with_value(
         template,
         %{key: key, inner_content: inner_content},
         params,
         _env
       ) do
    case get_value_from_params(inner_content, params) do
      {:ok, value} -> String.replace(template, key, stringify_value(value))
      :no_value -> template
    end
  end

  defp replace_template_key_with_code_execution(
         template,
         capture,
         _params,
         env
       ) do
    execution_result = CodeEvaluation.eval(capture, env)
    String.replace(template, capture.key, stringify_value(execution_result))
  end

  # Used by `run/2` (plain string substitution, no positional params).
  # Returns {:ok, value} or :no_value.
  defp get_value_from_params(key, params) when is_binary(key) do
    {key, modifier} = split_key_modifier(key)

    case Map.get(params, key) do
      nil -> :no_value
      value -> {:ok, maybe_apply_modifier(value, key, modifier)}
    end
  end

  # Used by `run_generate_positional_params/2`.
  # Returns {:ok, value, type_or_modifier} or :no_value.
  # type_or_modifier is one of: nil, :inline, or a CH type string like "UInt64".
  defp get_value_with_type_info(key, params) when is_binary(key) do
    {key, suffix} = split_key_modifier(key)

    case Map.get(params, key) do
      nil ->
        :no_value

      value ->
        case classify_suffix(suffix) do
          :human_readable -> {:ok, human_readable(value), nil}
          :inline -> {:ok, value, :inline}
          {:ch_type, type} -> {:ok, value, type}
          nil -> {:ok, value, nil}
        end
    end
  end

  defp split_key_modifier(key) do
    case String.split(key, ":", parts: 2) do
      [key] -> {key, nil}
      [key, modifier] -> {key, modifier}
    end
  end

  defp classify_suffix(nil), do: nil
  defp classify_suffix("human_readable"), do: :human_readable
  defp classify_suffix("inline"), do: :inline

  defp classify_suffix(suffix) do
    if Sanbase.Clickhouse.Type.known_ch_type?(suffix) do
      {:ch_type, suffix}
    else
      raise TemplateEngineError,
        message: "Unsupported or mistyped modifier '#{suffix}'"
    end
  end

  defp maybe_apply_modifier(value, _key, modifier) do
    case classify_suffix(modifier) do
      :human_readable -> human_readable(value)
      # :inline, {:ch_type, _}, nil — no transformation in the run/2 path
      _ -> value
    end
  end
end
