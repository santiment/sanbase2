defmodule Sanbase.Insight.PostAdmin do
  import Ecto.Query

  alias Sanbase.Insight.Post

  def custom_index_query(_conn, _schema, query) do
    from(r in query, preload: [:user, :featured_item])
  end

  def custom_show_query(_conn, _schema, query) do
    from(r in query, preload: [:user, :featured_item, :price_chart_project])
  end

  def index(_) do
    [
      id: nil,
      title: nil,
      is_featured: %{value: &is_featured/1},
      is_pulse: nil,
      state: nil,
      ready_state: nil,
      moderation_comment: nil,
      user_id: %{
        value: fn p ->
          p.user.email || p.user.username
        end
      }
    ]
  end

  def form_fields(_schema, insight \\ %Post{}) do
    [
      id: %{update: :readonly, create: :readonly},
      title: %{update: :readonly, create: :readonly},
      short_desc: %{update: :readonly, create: :readonly},
      prediction: %{
        choices: [
          {"Heavy Bullish", "heavy_bullish"},
          {"Semi Bullish", "semi_bullish"},
          {"Heavy Bearish", "heavy_bearish"},
          {"Semi Bearish", "semi_bearish"},
          {"Unspecified", "unspecified"},
          {"None", "none"}
        ]
      },
      is_featured: %{type: :boolean, opts: [value: is_featured_string(insight)]},
      is_pulse: nil,
      is_paywall_required: nil,
      state: %{
        choices: [
          {"Awaiting Approval", Post.awaiting_approval_state()},
          {"Approved", Post.approved_state()},
          {"Decline", Post.declined_state()}
        ]
      },
      ready_state: %{update: :readonly, create: :readonly},
      moderation_comment: %{type: :textarea},
      user_id: %{
        update: :readonly,
        create: :readonly,
        help_text: insight.user.email || insight.user.username
      },
      price_chart_project_id: %{update: :readonly, create: :readonly},
      text: %{update: :readonly, create: :readonly, type: :textarea, rows: 5}
    ]
  end

  def resource_actions(_conn) do
    [
      toggle_featured: %{name: "Toggle featured", action: fn _c, p -> toggle_featured(p) end},
      toggle_pulse: %{name: "Toggle pulse", action: fn _c, p -> toggle_pulse(p) end},
      toggle_paywall_required: %{
        name: "Toggle paywall",
        action: fn _c, p -> toggle_paywall(p) end
      }
    ]
  end

  def after_update(conn, insight) do
    is_featured = conn.params["post"]["is_featured"] |> String.to_existing_atom()

    :ok = Sanbase.Insight.Search.update_document_tokens(insight.id)
    toggle_featured(insight, is_featured)
  end

  def is_featured(insight) do
    insight.featured_item != nil
  end

  def is_featured_string(insight) do
    is_featured(insight) |> Atom.to_string()
  end

  def toggle_pulse(insight) do
    update_insight(insight, %{is_pulse: !insight.is_pulse})
  end

  def toggle_paywall(insight) do
    update_insight(insight, %{is_paywall_required: !insight.is_paywall_required})
  end

  def toggle_featured(insight, is_featured \\ nil) do
    is_featured = if is_featured != nil, do: is_featured, else: !is_featured(insight)

    Sanbase.FeaturedItem.update_item(insight, is_featured)
    |> case do
      :ok -> {:ok, insight}
      {:error, reason} -> {:error, insight, reason}
    end
  end

  def update_insight(insight, args) do
    insight
    |> Sanbase.Insight.Post.update_changeset(args)
    |> Sanbase.Repo.update()
  end

  def create_changeset(schema, attrs) do
    Post.create_changeset(schema, attrs)
  end

  def update_changeset(entry, attrs) do
    Post.update_changeset(entry, attrs)
  end
end
