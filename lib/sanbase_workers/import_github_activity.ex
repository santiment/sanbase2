defmodule SanbaseWorkers.ImportGithubActivity do
  use Faktory.Job

  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Github
  alias Sanbase.Github.Store
  alias Sanbase.Influxdb.Measurement
  @github_archive "http://data.githubarchive.org/"

  faktory_options queue: "github_activity", retry: -1, reserve_for: 900

  def perform(archive) do
    Temp.track!

    datetime = archive
    |> Timex.parse!("%Y-%m-%d-%k", :strftime)
    |> Timex.to_datetime

    orgs = Github.available_projects
    |> Enum.map(&get_project_org/1)
    |> Enum.reject(&is_nil/1)
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
    |> Stream.map(&Poison.decode!/1)
    |> Stream.map(&get_repository_name/1)
    |> Stream.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn repo, counts ->
      reduce_repos_to_counts(repo, counts, orgs)
    end)
  end

  defp get_project_org(%Project{github_link: github_link} = project) do
    case Regex.run(~r{https://(?:www.)?github.com/(.+)}, github_link) do
      [_, github_path] ->
        org = github_path
        |> String.downcase
        |> String.split("/")
        |> hd

        {org, project}
      nil ->
        nil
    end
  end

  defp reduce_repos_to_counts(repo, counts, orgs) do
    repo_org = repo
    |> String.downcase
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

  defp get_repository_name(%{"repo" => %{"name" => name}}), do: name

  defp get_repository_name(%{"repository" => %{"name" => name}}), do: name

  defp get_repository_name(_), do: nil

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
