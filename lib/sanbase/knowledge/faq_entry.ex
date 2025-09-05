defmodule Sanbase.Knowledge.FaqEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "faq_entries" do
    field(:question, :string)
    field(:answer_markdown, :string)
    field(:answer_html, :string)
    field(:source_url, :string)

    timestamps()
  end

  def changeset(faq_entry, attrs) do
    faq_entry
    |> cast(attrs, [:question, :answer_markdown, :source_url])
    |> validate_required([:question, :answer_markdown])
    |> validate_url(:source_url)
    |> generate_html()
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn field, value ->
      case value do
        nil ->
          []

        "" ->
          []

        url ->
          case URI.parse(url) do
            %URI{scheme: scheme, host: host}
            when scheme in ["http", "https"] and is_binary(host) ->
              []

            _ ->
              [{field, "must be a valid URL"}]
          end
      end
    end)
  end

  defp generate_html(changeset) do
    case get_change(changeset, :answer_markdown) do
      nil ->
        changeset

      markdown ->
        case Earmark.as_html(markdown) do
          {:ok, html} ->
            sanitized_html = HtmlSanitizeEx.html5(html)
            put_change(changeset, :answer_html, sanitized_html)

          {:ok, html, _warnings} ->
            sanitized_html = HtmlSanitizeEx.html5(html)
            put_change(changeset, :answer_html, sanitized_html)

          {:error, html, _warnings} ->
            # Even with errors, Earmark still provides HTML output
            sanitized_html = HtmlSanitizeEx.html5(html)
            put_change(changeset, :answer_html, sanitized_html)

          {:error, _reason} ->
            add_error(changeset, :answer_markdown, "contains invalid markdown")
        end
    end
  end
end
