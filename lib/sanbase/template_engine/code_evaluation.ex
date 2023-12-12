defmodule Sanbase.TemplateEngine.CodeEvaluation do
  def eval(capture, env) do
    with true <- lang_supported?(capture),
         {:ok, result} <- do_eval(capture.inner_content, env) do
      result
    end
  end

  defp do_eval("", _env), do: {:ok, ""}
  defp do_eval(input, env), do: {:ok, Sanbase.SanLang.eval(input, env)}

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
