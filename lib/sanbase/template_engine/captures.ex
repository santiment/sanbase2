defmodule Sanbase.TemplateEngine.Captures do
  defmodule CaptureMap do
    defstruct [
      :code?,
      :key,
      :id,
      :lang,
      :lang_version,
      :inner_content
    ]
  end

  @doc ~s"""
  Extract the captures from the template. The captures are the keys that are enclosed in {{}}
  """
  @spec get(String.t()) :: {:ok, list(CaptureMap.t())}
  def get(template) do
    captures =
      template
      |> get_regex_captures()
      |> captures_to_maps()

    {:ok, captures}
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  # Private

  # Return a list in the format: [{"{{key}}", "key"}, {"{% 1 + 2  %}", "1 + 2"}}]
  # where elements are tuples. The first element of the tuple is the whole capture
  # and the second one is the trimmed inner content.
  defp get_regex_captures(template) do
    Regex.scan(~r/\{\{(?<capture_param>.*?)\}\}|\{\%(?<capture_code>.*?)\%\}/, template)
    |> Enum.map(fn
      [a, b] -> [a, String.trim(b)]
      [a, "", b] -> [a, String.trim(b)]
    end)
    |> Enum.uniq()
    |> Enum.with_index()
  end

  # Convert the
  defp captures_to_maps(captures) do
    lang_map = find_lang_definition_capture(captures)

    capture_maps =
      captures
      |> Enum.map(fn {[key, inner], id} ->
        parse_template_inner(key, inner, id, lang_map)
      end)

    raise_if_captures_contain_brackets(capture_maps)

    capture_maps
  end

  defp parse_template_inner("{%" <> _ = key, inner, id, lang_map) do
    # The template {% lang=san:1.0 %} should be replaced with the
    # empty string, as it should not evaluate to anything.
    inner = if(id == lang_map.capture_id, do: "", else: inner)

    %CaptureMap{
      code?: true,
      key: key,
      id: id,
      lang: lang_map.lang,
      lang_version: lang_map.version,
      inner_content: inner
    }
  end

  defp parse_template_inner("{{" <> _ = key, inner, id, _lang_map) do
    %CaptureMap{
      code?: false,
      key: key,
      id: id,
      lang: nil,
      lang_version: nil,
      inner_content: inner
    }
  end

  defp find_lang_definition_capture(captures) do
    lang_defining_capture =
      Enum.find(captures, fn {[key, inner], _index} ->
        String.starts_with?(key, "{%") and String.starts_with?(inner, "lang=")
      end)

    case lang_defining_capture do
      nil ->
        %{lang: "san", version: "1.0", capture_id: nil}

      {[_, definition], index} ->
        # Regex that matches lang=<lang>:<version
        case Regex.scan(~r/lang\s*=\s*([\w\d]+):([\w\d\.]+)/, definition) do
          [[_, lang, version]] -> %{lang: lang, version: version, capture_id: index}
          _ -> raise_lang_definition_error(definition)
        end
    end
  end

  defp raise_lang_definition_error(definition) do
    raise(Sanbase.TemplateEngine.TemplateEngineException,
      message: """
      The lang definition is invalid: #{definition}.
      It must be in the format: lang=<lang>:<version> (eg. lang=san:1.0)
      """
    )
  end

  defp raise_if_captures_contain_brackets(captures) do
    case Enum.find(captures, fn map -> String.contains?(map.inner_content, ["{", "}"]) end) do
      nil ->
        :ok

      %{key: key} ->
        raise(Sanbase.TemplateEngine.TemplateEngineException,
          message: """
          Error parsing the template. The template contains a key that itself contains
          { or }. This means that an opening or closing bracket is missing.

          Template: #{inspect(key)}
          """
        )
    end
  end
end
