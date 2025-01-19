defmodule Sanbase.DiscordBot.Insights do
  import Ecto.Query

  def run(n) do
    data =
      fetch_last_insights(n)
      |> Enum.map(&format_insight/1)
      |> Jason.encode!()

    File.write!("insights.json", data)
  end

  def format_insight(insight) do
    data = """
    Title: #{insight.title}
    Author: @#{insight.user.username}
    Text: #{insight.text |> Floki.parse_document!() |> Floki.text()}
    Published At: #{NaiveDateTime.to_date(insight.published_at) |> to_string()}
    Tags: #{insight.tags |> Enum.map(& &1.name) |> Enum.join(", ")}
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
