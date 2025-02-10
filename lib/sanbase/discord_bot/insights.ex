defmodule Sanbase.DiscordBot.Insights do
  @moduledoc false
  import Ecto.Query

  def run(n) do
    data =
      n
      |> fetch_last_insights()
      |> Enum.map(&format_insight/1)
      |> Jason.encode!()

    File.write!("insights.json", data)
  end

  def format_insight(insight) do
    data = """
    Title: #{insight.title}
    Author: @#{insight.user.username}
    Text: #{insight.text |> Floki.parse_document!() |> Floki.text()}
    Published At: #{insight.published_at |> NaiveDateTime.to_date() |> to_string()}
    Tags: #{Enum.map_join(insight.tags, ", ", & &1.name)}
    """

    metadata = %{
      id: insight.id,
      link: "https://insights.santiment.net/read/#{insight.id}",
      dt: insight.published_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    }

    %{id: insight.id, data: data, metadata: metadata}
  end

  def fetch_last_insights(n \\ 1) do
    query =
      from(
        p in Sanbase.Insight.Post,
        where:
          p.is_deleted == false and p.is_hidden == false and p.state == "approved" and
            p.ready_state == "published",
        order_by: [desc: p.id],
        preload: [:user, :tags],
        limit: ^n
      )

    Sanbase.Repo.all(query)
  end
end
