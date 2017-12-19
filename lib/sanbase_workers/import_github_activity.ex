defmodule SanbaseWorkers.ImportGithubActivity do
  use Faktory.Job

  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Github
  alias Sanbase.Github.Store
  alias Sanbase.Influxdb.Measurement
  @github_archive "http://data.githubarchive.org/"

  faktory_options queue: "github_activity", retry: -1, reserve_for: 600

  def perform(archive) do
    Temp.track!

    datetime = archive
    |> Timex.parse!("%Y-%m-%d-%k", :strftime)
    |> Timex.to_datetime

    orgs = Github.available_projects
    |> Enum.map(&get_project_org/1)
    |> Map.new()

    Logger.info("Scanning activity for github users #{Map.keys(orgs) |> inspect}")

    archive
    |> download
    |> stream_process_cleanup(orgs, datetime)
  end

  defp download(archive) do
    {:ok, temp_filepath} = Temp.path(%{prefix: archive, suffix: ".json.gz"})

    output_file = File.open!(temp_filepath, [:write, :delayed_write])

    Logger.info("Downloading archive #{archive} to #{temp_filepath}")

    %HTTPoison.AsyncResponse{id: request_ref} = HTTPoison.get!(@github_archive <> archive <> ".json.gz", %{}, stream_to: self(), recv_timeout: 60_000)

    :ok = stream_loop(request_ref, output_file)

    File.close(output_file)

    temp_filepath
  end

  defp stream_loop(request_ref, output_file) do
    receive do
      %HTTPoison.AsyncStatus{id: ^request_ref, code: 200} ->
        stream_loop(request_ref, output_file)
      %HTTPoison.AsyncHeaders{id: ^request_ref} ->
        stream_loop(request_ref, output_file)
      %HTTPoison.AsyncEnd{id: ^request_ref} ->
        :ok
      %HTTPoison.AsyncChunk{chunk: data, id: ^request_ref} ->
        :ok = IO.binwrite(output_file, data)
        stream_loop(request_ref, output_file)
    end
  end

  defp stream_process_cleanup(filename, orgs, datetime) do
    File.stream!(filename, [:compressed])
    |> reduce_to_counts(orgs)
    |> store_counts(orgs, datetime)

    File.rm!(filename)
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
