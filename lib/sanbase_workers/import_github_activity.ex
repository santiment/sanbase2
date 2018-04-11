defmodule SanbaseWorkers.ImportGithubActivity do
  use Faktory.Job

  require Logger

  require Sanbase.Utils.Config

  alias Sanbase.Github
  alias Sanbase.Github.Store
  alias Sanbase.Influxdb.Measurement
  alias ExAws.S3
  alias Sanbase.Utils.Config

  @github_archive "http://data.gharchive.org/"

  faktory_options(queue: "default", retry: -1, reserve_for: 900)

  def perform(archive) do
    Temp.track!()

    datetime =
      archive
      |> Timex.parse!("%Y-%m-%d-%k", :strftime)
      |> Timex.to_datetime()

    orgs =
      Github.available_projects()
      |> Enum.map(fn project ->
        {Github.get_project_org(project), project}
      end)
      |> Map.new()

    Logger.info("Scanning activity for github users #{Map.keys(orgs) |> inspect}")

    archive
    |> download
    |> stream_process_cleanup(orgs, datetime)

    Map.values(orgs)
    |> Enum.each(&Github.ProcessedGithubArchive.mark_as_processed(&1.id, archive))
  end

  defp download(archive) do
    case download_from_s3(archive) do
      {:error, error} ->
        Logger.info(
          "Can't download #{archive} from S3. Downloading from archive: #{inspect(error)}"
        )

        download_from_archive(archive)

      {:ok, filepath} ->
        filepath
    end
  end

  defp download_from_s3(archive) do
    {:ok, temp_filepath} = Temp.path(%{prefix: archive, suffix: ".json.gz"})

    with {:ok, _} <- S3.head_object(Config.get(:s3_bucket), s3_path(archive)) |> ExAws.request(),
         {:ok, :done} <-
           S3.download_file(Config.get(:s3_bucket), s3_path(archive), temp_filepath)
           |> ExAws.request() do
      Logger.info("Downloaded #{archive} from S3 into #{temp_filepath}")
      {:ok, temp_filepath}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp download_from_archive(archive) do
    {:ok, temp_filepath} = Temp.path(%{prefix: archive, suffix: ".json.gz"})

    output_file = File.open!(temp_filepath, [:write, :delayed_write])

    Logger.info("Downloading archive #{archive} to #{temp_filepath}")

    %HTTPoison.AsyncResponse{id: request_ref} =
      HTTPoison.get!(
        @github_archive <> archive <> ".json.gz",
        %{},
        stream_to: self(),
        recv_timeout: 60_000,
        follow_redirect: true
      )

    :ok = stream_loop(request_ref, output_file)

    File.close(output_file)

    Logger.info("Uploading archive #{archive} to S3...")

    temp_filepath
    |> S3.Upload.stream_file()
    |> S3.upload(
      Config.get(:s3_bucket),
      s3_path(archive),
      content_type: "application/json",
      content_encoding: "gzip"
    )
    |> ExAws.request!()

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

  defp s3_path(archive) do
    [year, month | _rest] = String.split(archive, "-")

    "#{year}/#{month}/#{archive}.json.gz"
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

  defp reduce_repos_to_counts(repo, counts, orgs) do
    repo_org =
      repo
      |> String.downcase()
      |> String.split("/")
      |> hd

    if Map.has_key?(orgs, repo_org) do
      {_value, map} =
        Map.get_and_update(counts, repo_org, fn
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
        tags: [],
        name: orgs[org].ticker
      }
    end)
    |> Store.import()
  end
end
