defmodule Sanbase.SanLang do
  @moduledoc ~s"""
  SanLang's function is to evaluate simple one-line expressions. These expressions can be used
  in Santiment Queries.

  The following list explains the capabilities of the language
    - Simple arithmetic operations: +, -, *, /
      - 1 + 2 * 3 + 10 => 17
      - 1 / 5 => 0.2
    - Access to environment variables passed via the env parameter. These variables
      are accessed by prefixing their name with '@', like @projects, @owner, etc.
    - Access operator that can be chained:
      - @owner["email"] => test@santiment.net
      - @projects["bitcoin"]["infrastructure"] => BTC
    - Named functions:
      - pow(2, 10) => 1024
      - div(10, 5) => 2
    - Named functions with lambda function as arguments:
      - map([1,2,3], fn x -> x + 10 end) => [11, 12, 13]
      - filter([1,2,3], fn x -> x > 1 end) => [2, 3]
    - Comparisons and boolean expressions: ==, !=, >, <, >=, <=, and, or
      - 1 + 2 * 3 + 10 > 10 => true
  """
  alias Sanbase.Environment
  alias Sanbase.SanLang.Interpreter

  import Sanbase.Utils.Transform, only: [to_bang: 1]

  @doc ~s"""
  Evaluates the given input string as a SanLang expression and returns the result.

  The `env` parameter is optional and defaults to an empty environment. It can be used to pass
  local bindings (var) or environment variable bindings (@env_var).
  """
  @spec eval(String.t(), Environment.t()) :: {:ok, any()} | {:error, String.t()}
  def eval(input, env \\ Environment.new()) when is_binary(input) do
    with {:ok, ast} <- string_to_ast(input),
         result <- Interpreter.eval(ast, env) do
      {:ok, result}
    else
      error ->
        handle_error(error)
    end
  end

  @doc ~s"""
  Same as eval/2, but raises on error.
  """
  @spec eval(String.t(), Environment.t()) :: any() | no_return
  def eval!(input, env \\ Environment.new()) when is_binary(input) do
    eval(input, env) |> to_bang()
  end

  defp string_to_ast(input) when is_binary(input) do
    input_charlist = String.to_charlist(input)

    with {:ok, tokens, _} <- :san_lang_lexer.string(input_charlist),
         {:ok, ast} <- :san_lang_parser.parse(tokens) do
      {:ok, ast}
    end
  end

  defp handle_error({:error, {{line, column}, :san_lang_parser, errors_list}}) do
    {:error,
     """
     Parser error on location #{line}:#{column}
     Reason: #{to_string(errors_list)}
     """}
  end

  defp handle_error({:error, {{line, column}, :san_lang_lexer, error_tuple}, _}) do
    case error_tuple do
      {:illegal, token} ->
        {:error,
         """
         Lexer error on location #{line}:#{column}
         Illegal token '#{to_string(token)}'
         """}

      tuple ->
        {:error,
         """
         Lexer error on location #{line}:#{column}
         Reason: #{inspect(tuple)}
         """}
    end
  end
end
