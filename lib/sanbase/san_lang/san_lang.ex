defmodule Sanbase.SanLang do
  alias Sanbase.SanLang.Environment
  alias Sanbase.SanLang.Interpreter

  def eval(input, env \\ Environment.new()) when is_binary(input) do
    input_charlist = String.to_charlist(input)

    with {:ok, tokens, _} <- :san_lang_lexer.string(input_charlist),
         {:ok, ast} <- :san_lang_parser.parse(tokens),
         {:ok, result} <- Interpreter.eval(ast, env) do
      {:ok, result}
    end
  end
end
