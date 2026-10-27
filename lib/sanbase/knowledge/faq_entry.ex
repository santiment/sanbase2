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
    field(:embedding, Pgvector.Ecto.Vector)
    field(:is_deleted, :boolean, default: false)

    # Drafts are invisible to every read path that feeds answers, search or
    # exports until a team member publishes them. `origin` records where the
    # entry was created; `internal_notes` is reviewer context and is never served.
    field(:status, Ecto.Enum, values: [:draft, :published], default: :published)
    field(:origin, Ecto.Enum, values: [:admin, :mcp], default: :admin)
    field(:internal_notes, :string)
    field(:reviewed_at, :naive_datetime)

    belongs_to(:created_by, Sanbase.Accounts.User, type: :id)
    belongs_to(:reviewed_by, Sanbase.Accounts.User, type: :id)

    many_to_many(:tags, Sanbase.Tag,
      join_through: "faq_entries_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    timestamps()
  end

  @allowed_tags ["code", "subscription", "api", "metrics", "payment", "sanbase"]

  @doc "The tags an FAQ entry can carry."
  def allowed_tags(), do: @allowed_tags

  def changeset(faq_entry, attrs) do
    faq_entry
    |> cast(attrs, [:question, :answer_markdown, :source_url, :internal_notes])
    |> validate_required([:question, :answer_markdown])
    |> validate_url(:source_url)
    |> unique_constraint(:question,
      name: :faq_entries_question_index,
      message: "an FAQ entry with this exact question already exists"
    )
    |> generate_html()
    |> Sanbase.Tag.put_tags(attrs)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn field, value ->
      validate_url_format(field, value)
    end)
  end

  defp validate_url_format(field, value) do
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
