defmodule Sanbase.Insight.PostAdmin do
  import Ecto.Query

  alias Sanbase.Insight.Post

  def custom_index_query(_conn, _schema, query) do
    from(r in query, preload: [:user, :featured_item])
  end

  def custom_show_query(_conn, _schema, query) do
    from(r in query, preload: [:user, :featured_item])
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
          user = Sanbase.Accounts.get_user!(p.user_id)
          user.email || user.username
        end
      }
    ]
  end

  def form_fields(schema) do
    IO.inspect(schema, label: "schema")

    [
      is_featured: %{type: :boolean, opts: [value: "true"]},
      is_pulse: nil,
      is_paywall_required: nil,
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
      state: %{
        choices: [
          {"Awaiting Approval", Post.awaiting_approval_state()},
          {"Approved", Post.approved_state()},
          {"Decline", Post.declined_state()}
        ]
      },
      moderation_comment: %{type: :richtext}
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

  def toggle_featured(insight) do
    Sanbase.FeaturedItem.update_item(insight, !is_featured(insight))
    |> case do
      :ok -> {:ok, insight}
      {:error, reason} -> {:error, insight, reason}
    end
  end

  def update_insight(insight, args) do
    insight
    |> Sanbase.Insight.Post.update_changeset(args)
    |> IO.inspect()
    |> Sanbase.Repo.update()
  end

  def create_changeset(schema, attrs) do
    # do whatever you want, must return a changeset
    Post.create_changeset(schema, attrs)
  end

  def update_changeset(entry, attrs) do
    # do whatever you want, must return a changeset
    Post.update_changeset(entry, attrs)
  end
end
