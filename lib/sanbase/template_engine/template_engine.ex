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

    with {:ok, captures} <- TemplateEngine.Captures.get(template) do
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
    run(template, opts) |> to_bang
  end

  @doc ~s"""
  Run the template engine and generate a new template and a list of positional params
  that can be used in Clickhouse queries.

  The templates are replaced not with the actual value, but with a placeholder like ?1, ?2, etc.
  which correspond to the position of the value in the list of positional params.
  The indexes start from 1.

    Examples:
      iex> run_generate_positional_params("My name is {{name}}", params: %{name: "San"})
      {:ok, {"My name is ?1", ["San"]}}

      iex> run_generate_positional_params("{{name}} is {% 20 + 8 %} years old", params: %{name: "Tom"})
      {:ok, {"?1 is ?2 years old", ["Tom", 28]}}

      iex> run_generate_positional_params("param name is reused {{name}} {{name}} is {% 20 + 8 %} years old {{name}}", params: %{name: "Tom"})
      {:ok, {"param name is reused ?1 ?1 is ?2 years old ?1", ["Tom", 28]}}
  """
  @spec run_generate_positional_params(String.t(), opts) :: {String.t(), list(any())}
  def run_generate_positional_params(template, opts) do
    params = Keyword.get(opts, :params, %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    env = Keyword.get(opts, :env, Sanbase.SanLang.Environment.new())

    with {:ok, captures} <- TemplateEngine.Captures.get(template) do
      result = do_run_generate_positional_params(template, captures, params, env)
      {:ok, result}
    end
  end

  # Private

  defp do_run_generate_positional_params(template, captures, params, env) do
    {sql, args, _position} =
      Enum.reduce(
        captures,
        {template, _args = [], _position = 1},
        fn
          %{code?: false} = capture_map, {template_acc, args_acc, position} ->
            case get_value_from_params(capture_map.inner_content, params) do
              {:ok, value} ->
                template_acc = String.replace(template_acc, capture_map.key, "?#{position}")
                args_acc = [value | args_acc]
                {template_acc, args_acc, position + 1}

              :no_value ->
                raise_positional_params_error(template, capture_map.inner_content, params, env)
            end

          %{code?: true} = capture_map, {template_acc, args_acc, position} ->
            execution_result = CodeEvaluation.eval(capture_map, env)
            template_acc = String.replace(template_acc, capture_map.key, "?#{position}")
            args_acc = [execution_result | args_acc]
            {template_acc, args_acc, position + 1}
        end
      )

    {sql, Enum.reverse(args)}
  end

  defp raise_positional_params_error(template, key, params, env) do
    raise(TemplateEngineError,
      message: """
      Error parsing the template. The template contains a key that is not present in the params map.

      Key: #{inspect(key)}
      Template: #{inspect(template)}
      Params: #{inspect(params)}
      Env: #{inspect(env)}
      """
    )
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
    {key, modifier} =
      case String.split(key, ":") do
        [key] -> {key, nil}
        [key, modifier] -> {key, modifier}
      end

    case Map.get(params, key) do
      nil -> :no_value
      value -> {:ok, maybe_apply_modifier(value, key, modifier)}
    end
  end

  defp maybe_apply_modifier(value, _key, "human_readable"), do: human_readable(value)
  defp maybe_apply_modifier(value, _key, nil), do: value

  defp maybe_apply_modifier(_, key, modifier),
    do:
      raise(TemplateEngineError,
        message: """
        Unsupported or mistyped modifier '#{modifier}' for key '#{key}'
        """
      )
end
