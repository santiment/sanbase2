defmodule SanbaseWorkers.ImportGithubActivity do
  use Faktory.Job
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://data.githubarchive.org"
  plug Tesla.Middleware.Logger

  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Github.Store
  alias Sanbase.Github.Measurement
  alias Sanbase.Repo

  @github_archive "http://data.githubarchive.org/"

  faktory_options queue: "github_activity", retry: -1, reserve_for: 60

  import Ecto.Query

  def perform(archive) do
    Temp.track!

    datetime = archive
    |> Timex.parse!("%Y-%m-%d-%H", :strftime)
    |> Timex.to_datetime

    orgs = Project
    |> where([p], not is_nil(p.github_link) and not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    |> Repo.all
    |> Enum.map(&get_project_org/1)
    |> Map.new()

    Logger.info("Scanning activity for github users #{Map.keys(orgs) |> inspect}")

    archive
    |> download
    |> File.stream!([:compressed])
    |> reduce_to_counts(orgs)
    |> store_counts(orgs, datetime)
  end

  defp download(archive) do
    {:ok, temp_filepath} = Temp.path(%{prefix: archive, suffix: ".json.gz"})

    Logger.info("Downloading archive #{archive} to #{temp_filepath}")

    %Tesla.Env{status: 200, body: body} = get(archive <> ".json.gz")

    File.write!(temp_filepath, body)

    temp_filepath
  end

  defp reduce_to_counts(stream, orgs) do
    stream
    |> Enum.reduce(%{}, fn line, counts ->
      reduce_events_to_counts(line, counts, orgs)
    end)
  end

  defp get_project_org(%Project{github_link: "https://github.com/" <> github_path} = project) do
    org = github_path
    |> String.split("/")
    |> hd

    {org, project}
  end

  defp reduce_events_to_counts(line, counts, orgs) do
    repo_org = line
    |> Poison.decode!()
    |> get_in(["repo", "name"])
    |> String.split("/")
    |> hd

    if Map.has_key?(orgs, repo_org) do
      {_value, map} = Map.get_and_update(counts, repo_org, fn
        nil -> {nil, 1}
        value -> {value, value + 1}
      end)

      map
    else
      counts
    end
  end

  defp store_counts(counts, orgs, datetime) do
    counts
    |> Enum.map(fn {org, count} ->
      %Measurement{
        timestamp: DateTime.to_unix(datetime, :nanosecond),
        fields: %{activity: count},
        tags: [source: "githubarchive"],
        name: orgs[org].ticker
      }
    end)
    |> Store.import
  end
end
