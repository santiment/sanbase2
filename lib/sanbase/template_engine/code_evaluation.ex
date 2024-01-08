defmodule Sanbase.TemplateEngine.CodeEvaluation do
  @moduledoc ~s"""
  Evaluate the code inside a template capture {% %}
  """

  alias Sanbase.TemplateEngine.Captures.CaptureMap
  alias Sanbase.SanLang

  @doc ~s"""
  Given the capture map produced by the template engine, evaluate the code inside the capture.
  The inner_content of the capture map is evaluated, using the lang and lang_version
  specified.
  """
  @spec eval(CaptureMap.t(), SanLang.Environment.t()) :: {:ok, any()} | {:error, String.t()}
  def eval(capture, env) do
    with true <- lang_supported?(capture),
         {:ok, result} <- do_eval(capture.inner_content, capture.lang, env) do
      result
    end
  end

  # Private functions

  defp do_eval("", _lang = "san", _env), do: {:ok, ""}
  defp do_eval(input, _lang = "san", env), do: Sanbase.SanLang.eval(input, env)

  defp lang_supported?(%{lang: "san", lang_version: ver}) do
    case ver do
      "1.0" ->
        true

      _ ->
        {:error,
         "Unsupported version for the lang 'san': #{ver}. The supported versions are: 1.0"}
    end
  end

  defp lang_supported?(%{lang: lang}) do
    {:error, "Unsupported lang: #{lang}. The only supported language is 'san'"}
  end
end
