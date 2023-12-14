defmodule Sanbase.SanLang do
  alias Sanbase.SanLang.Environment
  alias Sanbase.SanLang.Interpreter

  import Sanbase.Utils.Transform, only: [to_bang: 1]

  @doc ~s"""

  """
  @spec eval(String.t(), Environment.t()) :: {:ok, any()} | {:error, String.t()}
  def eval(input, env \\ Environment.new()) when is_binary(input) do
    input_charlist = String.to_charlist(input)

    with {:ok, tokens, _} <- :san_lang_lexer.string(input_charlist),
         {:ok, ast} <- :san_lang_parser.parse(tokens),
         result <- Interpreter.eval(ast, env) do
      {:ok, result}
    else
      {:error, {line, :san_lang_parser, errors_list}} ->
        {:error,
         """
         Parser error on line #{line}: #{to_string(errors_list)}
         """}

      {:error, {line, :san_lang_lexer, error_tuple}, _} ->
        case error_tuple do
          {:illegal, token} ->
            {:error,
             """
             Lexer error on line #{line}: Illegal token '#{to_string(token)}'
             """}

          tuple ->
            {:error,
             """
             Lexer error on line #{line}: #{inspect(tuple)}
             """}
        end
    end
  end

  @doc ~s"""
  Same as eval/2, but raises on error
  """
  @spec eval(String.t(), Environment.t()) :: any() | no_return
  def eval!(input, env \\ Environment.new()) when is_binary(input) do
    eval(input, env) |> to_bang()
  end
end
