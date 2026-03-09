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
  Run the template engine and generate a new template and a map of named params
  that can be used in Clickhouse queries.

  The templates are replaced not with the actual value, but with a typed placeholder
  like `{limit:UInt8}`, `{slug:String}`, etc. which correspond to the values
  in the returned params map.

  Supports:
  - `{{key:inline}}` — direct string substitution (no placeholder, validated for safety)
  - `{{key:UInt64}}` — explicit CH type override (any known CH type)
  - `{{key}}` — auto-inferred type from the Elixir value
  - `{% code %}` — code evaluation, auto-inferred type

    Examples:
      iex> run_generate_positional_params("My name is {{name}}", params: %{name: "San"})
      {:ok, {"My name is {name:String}", %{"name" => "San"}}}

      iex> run_generate_positional_params("{{name}} is {% 20 + 8 %} years old", params: %{name: "Tom"})
      {:ok, {"{name:String} is {expr_1:Int32} years old", %{"name" => "Tom", "expr_1" => 28}}}

      iex> run_generate_positional_params("param name is reused {{name}} {{name}} is {% 20 + 8 %} years old {{name}}", params: %{name: "Tom"})
      {:ok,
       {"param name is reused {name:String} {name:String} is {expr_1:Int32} years old {name:String}",
        %{"name" => "Tom", "expr_1" => 28}}}
  """
  @spec run_generate_positional_params(String.t(), opts) :: {String.t(), map()}
  def run_generate_positional_params(template, opts) do
    params = Keyword.get(opts, :params, %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    env = Keyword.get(opts, :env, Sanbase.SanLang.Environment.new())

    with {:ok, captures} <- TemplateEngine.Captures.extract_captures(template),
         {:ok, result} <- do_run_generate_positional_params(template, captures, params, env) do
      {:ok, result}
    end
  end

  # Private

  # Transform a template with `{{key}}` placeholders into a ClickHouse query with
  # typed named parameters (`{from:Int32}`, `{slug:String}`, etc.) and a matching
  # parameter map.
  #
  # ## Placeholder modes
  #
  # Each `{{key}}` placeholder is classified into one of these modes:
  #
  #   - **Inline** (`{{key:inline}}`) — the value is substituted directly into the SQL
  #     string (no positional param). Only alphanumeric, underscore, and dot characters
  #     are allowed (validated to prevent injection).
  #
  #   - **Value** (`{{key}}` or `{{key:UInt64}}`) — the value becomes a positional
  #     parameter. The ClickHouse type is either inferred from the Elixir value or
  #     taken from the explicit override.
  #
  #   - **Human-readable** (`{{key:human_readable}}`) — the value is formatted for
  #     display (e.g., `100000` → `"100,000.00"`) and then treated as a positional
  #     String parameter.
  #
  #   - **Code** (`{% expr %}`) — the expression is evaluated and the result becomes
  #     a positional parameter with an inferred type. Code captures are never deduplicated.
  #
  # ## Deduplication
  #
  # When the same key appears multiple times, we want to reuse the same named
  # parameter instead of creating duplicates. The dedup key is a tuple of
  # `{base_key, mode, ch_type}`:
  #
  #   - `{{slug}}` twice → same dedup key `{"slug", :value, "String"}` → reuses `{slug:String}`
  #   - `{{slug}}` and `{{slug:human_readable}}` → different modes → separate parameters
  #   - `{{num}}` and `{{num:UInt8}}` → same mode `:value` but different ch_type →
  #     separate parameters
  #   - `{{num:UInt8}}` twice → same dedup key → reuses the same parameter name
  #
  # ## Accumulator
  #
  # The reduce accumulator is a 6-tuple:
  # `{sql, args, errors, position, key_positions, used_param_names}`
  #
  #   - `sql` — the template string being progressively rewritten
  #   - `args` — string-keyed argument map
  #   - `errors` — collected missing-parameter errors
  #   - `position` — next available index for generated expression names
  #   - `key_positions` — map from dedup key to `{param_name, ch_type}` for reuse
  #   - `used_param_names` — set of already allocated parameter names
  defp do_run_generate_positional_params(template, captures, params, env) do
    {sql, args, errors, _position, _key_positions, _used_param_names} =
      Enum.reduce(
        captures,
        {template, _args = %{}, _errors = [], _position = 0, _key_positions = %{},
         _used_param_names = MapSet.new()},
        fn
          %{code?: false} = capture_map,
          {template_acc, args_acc, errors, position, key_positions, used_param_names} ->
            case get_value_with_type_info(capture_map.inner_content, params) do
              {:ok, value, :inline} ->
                inline_value = to_string(value)
                validate_inline_value!(inline_value, capture_map.key)
                template_acc = String.replace(template_acc, capture_map.key, inline_value)
                {template_acc, args_acc, errors, position, key_positions, used_param_names}

              {:ok, value, type_or_nil} ->
                ch_type = resolve_ch_type(value, type_or_nil)
                dedup_key = extract_dedup_key(capture_map.inner_content, ch_type)

                case Map.get(key_positions, dedup_key) do
                  nil ->
                    {base_key, _suffix} = split_key_modifier(capture_map.inner_content)
                    param_name = next_param_name(base_key, used_param_names, position)
                    placeholder = "{#{param_name}:#{ch_type}}"
                    template_acc = String.replace(template_acc, capture_map.key, placeholder)
                    args_acc = Map.put(args_acc, param_name, value)
                    key_positions = Map.put(key_positions, dedup_key, {param_name, ch_type})
                    used_param_names = MapSet.put(used_param_names, param_name)

                    {template_acc, args_acc, errors, position + 1, key_positions,
                     used_param_names}

                  {existing_param_name, existing_type} ->
                    placeholder = "{#{existing_param_name}:#{existing_type}}"
                    template_acc = String.replace(template_acc, capture_map.key, placeholder)
                    {template_acc, args_acc, errors, position, key_positions, used_param_names}
                end

              :no_value ->
                error = %{
                  error: :missing_parameter,
                  key: capture_map.key
                }

                errors = [error | errors]
                {template_acc, args_acc, errors, position, key_positions, used_param_names}
            end

          %{code?: true} = capture_map,
          {template_acc, args_acc, errors, position, key_positions, used_param_names} ->
            execution_result = CodeEvaluation.eval(capture_map, env)
            ch_type = resolve_ch_type(execution_result, nil)
            param_name = next_param_name("expr_#{position}", used_param_names, position)
            placeholder = "{#{param_name}:#{ch_type}}"
            template_acc = String.replace(template_acc, capture_map.key, placeholder)
            args_acc = Map.put(args_acc, param_name, execution_result)
            used_param_names = MapSet.put(used_param_names, param_name)
            {template_acc, args_acc, errors, position + 1, key_positions, used_param_names}
        end
      )

    case errors do
      [] ->
        {:ok, {sql, args}}

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

  defp extract_dedup_key(inner_content, ch_type) do
    {base_key, suffix} = split_key_modifier(inner_content)

    mode =
      case classify_suffix(suffix) do
        :human_readable -> :human_readable
        :inline -> :inline
        {:ch_type, _} -> :value
        nil -> :value
      end

    {base_key, mode, ch_type}
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

  defp get_value_from_params(key, params) when is_binary(key) do
    {key, modifier} = split_key_modifier(key)

    case Map.fetch(params, key) do
      :error -> :no_value
      {:ok, value} -> {:ok, maybe_apply_modifier(value, key, modifier)}
    end
  end

  defp get_value_with_type_info(key, params) when is_binary(key) do
    {key, suffix} = split_key_modifier(key)

    case Map.fetch(params, key) do
      :error ->
        :no_value

      {:ok, value} ->
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
      _ -> value
    end
  end

  defp next_param_name(base_name, used_param_names, suffix) do
    candidate = sanitize_param_name(base_name)

    cond do
      not MapSet.member?(used_param_names, candidate) ->
        candidate

      true ->
        next_param_name("#{candidate}_#{suffix}", used_param_names, suffix + 1)
    end
  end

  defp sanitize_param_name(name) do
    sanitized =
      name
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.trim("_")

    cond do
      sanitized == "" -> "param"
      String.match?(sanitized, ~r/^[0-9]/) -> "param_#{sanitized}"
      true -> sanitized
    end
  end
end
