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

  """

  import Sanbase.TemplateEngine.Utils, only: [human_readable: 1, stringify_value: 1]

  @type option :: {:params, map()} | {:env, Sanbase.SanLang.Environment.t()}
  @type opts :: [option()]

  @type template_inner_content_data :: %{
          code?: boolean,
          lang: String.t() | nil,
          lang_version: String.t() | nil,
          inner_content: String.t(),
          key: String.t()
        }

  defmodule TemplateEngineException do
    defexception [:message]
  end

  @doc ~s"""

    Examples:
      iex> run("My name is {{name}}", params: %{name: "San"})
      "My name is San"

      iex> run("{{a}}{{b}}{{a}}{{a}}", params: %{a: "1", b: 2})
      "1211"

      iex> run("SmallNum: {{small_num}}", params: %{small_num: 100})
      "SmallNum: 100"

      iex> run("MediumNum: {{medium_num}}", params: %{medium_num: 100000})
      "MediumNum: 100000"

      iex> run("Human Readable MediumNum: {{medium_num:human_readable}}", params: %{medium_num: 100000})
      "Human Readable MediumNum: 100,000.00"

      iex> run("BigNum: {{big_num}}", params: %{big_num: 999999999999})
      "BigNum: 999999999999"

      iex> run("Human Readable BigNum: {{big_num:human_readable}}", params: %{big_num: 999999999999})
      "Human Readable BigNum: 1,000.00 Billion"

      iex> run("{{timebound}} has human readable value {{timebound:human_readable}}", params: %{timebound: "3d"})
      "3d has human readable value 3 days"

      iex> run("{{[lang=san:1.0] 1 + 2 * 3 + 10}}")
      "17"

      iex> alias Sanbase.SanLang.Environment, as: Env
      iex> env = Env.put_env_bindings(Env.new(), %{"owner" => %{"email" => "test@santiment.net"}})
      iex> run(~s|My email is {{[lang=san:1.0] @owner["email"]}}|, env: env)
      "My email is test@santiment.net"

      iex> alias Sanbase.SanLang.Environment, as: Env
      iex> env = Env.put_env_bindings(Env.new(), %{"data" => ["a", "b", "c"]})
      iex> run(~s|My data is {{[lang=san:1.0] @data}}|, env: env)
      ~s|My data is ["a", "b", "c"]|
  """
  @spec run(String.t(), opts) :: String.t()
  def run(template, opts \\ []) do
    params = Keyword.get(opts, :params, %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    env = Keyword.get(opts, :env, Sanbase.SanLang.Environment.new())

    Enum.reduce(get_captures(template), template, fn
      %{code?: false} = map, template_acc ->
        replace_template_key_with_value(template_acc, map, params, env)

      %{code?: true} = map, template_acc ->
        replace_template_key_with_code_execution(template_acc, map, env)
    end)
  end

  @doc ~s"""
  TODO...
  """
  @spec run_generate_positional_params(String.t(), opts) :: {String.t(), list(any())}
  def run_generate_positional_params(template, opts) do
    params = Keyword.get(opts, :params, %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    env = Keyword.get(opts, :env, Sanbase.SanLang.Environment.new())

    {sql, args, _position} =
      Enum.reduce(
        get_captures(template),
        {template, _args = [], _position = 1},
        fn %{code?: false} = map, {template_acc, args_acc, position} ->
          case get_value_from_params(map.inner_content, params) do
            {:ok, value} ->
              template_acc = String.replace(template_acc, map.key, "?#{position}")
              args_acc = [value | args_acc]
              {template_acc, args_acc, position + 1}

            :no_value ->
              raise_positional_params_error(template, map.inner_content, params, env)
          end
        end
      )

    {sql, Enum.reverse(args)}
  end

  @doc ~s"""
  Extract the captures from the template. The captures are the keys that are enclosed in {{}}
  """
  def get_captures(template) do
    captures =
      Regex.scan(~r/\{\{(?<capture>.*?)\}\}/, template)
      |> Enum.uniq()
      |> Enum.map(fn [key_with_enclosing_curly_braces, inner] ->
        # The whole key (enclosed with {{}}) is needed for the find/replace step
        String.trim(inner)
        |> parse_template_inner()
        |> Map.put(:key, key_with_enclosing_curly_braces)
      end)

    raise_if_captures_contain_brackets(template, captures)

    captures
  end

  # Private

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

  def raise_if_captures_contain_brackets(template, captures) do
    if Enum.any?(captures, fn map -> String.contains?(map.inner_content, ["{", "}"]) end) do
      raise(TemplateEngineException,
        message: """
        Error parsing the template. The template contains a key that itself contains
        { or }. This means that an opening or closing bracket is missing.

        Template: #{inspect(template)}
        """
      )
    end
  end

  defp replace_template_key_with_value(
         template,
         %{key: key, inner_content: inner_content},
         params,
         env
       ) do
    case get_value_from_params(inner_content, params) do
      {:ok, value} -> String.replace(template, key, stringify_value(value))
      :no_value -> template
    end
  end

  defp replace_template_key_with_code_execution(
         template,
         %{lang: "san", lang_version: "1.0"} = map,
         env
       ) do
    execution_result = Sanbase.SanLang.eval(map.inner_content, env)
    String.replace(template, map.key, stringify_value(execution_result))
  end

  defp parse_template_inner("[lang=" <> rest) do
    [lang_with_version, rest] = String.split(rest, "]", parts: 2)
    [lang, version] = String.split(lang_with_version, ":")

    %{
      code?: true,
      lang: String.trim(lang),
      lang_version: String.trim(version),
      inner_content: String.trim(rest)
    }
  end

  defp parse_template_inner(inner_content) do
    %{code?: false, lang: nil, lang_version: nil, inner_content: String.trim(inner_content)}
  end

  defp get_value_from_params(key, params) when is_binary(key) do
    {key, modifier} =
      case String.split(key, ":") do
        [key] -> {key, nil}
        [key, modifier] -> {key, modifier}
      end

    case Map.has_key?(params, key) do
      true ->
        value = params[key]

        value =
          if modifier == "human_readable",
            do: human_readable(value),
            else: value

        {:ok, value}

      false ->
        :no_value
    end
  end
end
