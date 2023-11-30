defmodule Sanbase.SanLang.Parser do
  alias Sanbase.SanLang.Environment
  alias Sanbase.SanLang.Interpreter

  def parse_eval(input, env \\ Environment.new()) do
    with {:ok, tokens, _} <- :san_lang_lexer.string(input),
         {:ok, ast} <- :san_lang_parser.parse(tokens),
         {:ok, result} <- Interpreter.eval(ast, env) do
      {:ok, result}
    end
  end
end
