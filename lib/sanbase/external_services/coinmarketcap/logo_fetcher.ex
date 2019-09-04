defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

  alias Sanbase.Model.{Project, LatestCoinmarketcapData}
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo
  alias Sanbase.FileStore
  alias Sanbase.Utils.FileHash

  @log_tag "[CMC][LogoFetcher]"
  @size 64

  def run() do
    local_projects_map =
      Project.List.projects()
      |> Enum.map(fn %{slug: slug} = project -> {slug, project} end)
      |> Map.new()

    Logger.info("#{@log_tag} Started fetching logos from coinmarketcap.")

    Temp.track!()
    dir_path = Temp.mkdir!("logos")

    Map.keys(local_projects_map)
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn slugs ->
      {:ok, remote_projects} = CryptocurrencyInfo.fetch_data(slugs)

      Enum.each(remote_projects, fn remote_project ->
        update_project_logos(remote_project, local_projects_map, dir_path)
      end)

      remote_projects
    end)

    Temp.cleanup()

    Logger.info("#{@log_tag} Finished fetching logos from coinmarketcap.")
  end

  defp update_project_logos(remote_project, local_projects_map, dir_path) do
    url = remote_project.logo
    slug = remote_project.slug
    file_extension = Path.extname(url |> String.downcase())
    filename = slug <> file_extension

    case Map.get(local_projects_map, slug) do
      %Project{} = project ->
        with {:ok, local_filepath} <- download(url, dir_path, filename),
             {:logo_has_changed?, true} <-
               {:logo_has_changed?, logo_changed?(project, local_filepath)},
             {:ok, local_filepath} <- resize_image(local_filepath, dir_path, filename),
             {:ok, uploaded_filepath} <- upload(local_filepath),
             {:ok, _} <-
               update_local_project(project, %{
                 logo_url: uploaded_filepath
               }) do
          Logger.info("#{@log_tag} Successfully updated logos for project: #{project.slug}")
        else
          {:logo_has_changed?, false} ->
            :ok

          error ->
            error
        end

      _ ->
        :ok
    end
  end

  defp logo_changed?(project, filepath) do
    latest_cmc_data = LatestCoinmarketcapData.get_or_build(project.slug)
    {:ok, file_hash} = FileHash.calculate(filepath)

    case latest_cmc_data.logo_hash do
      ^file_hash ->
        Logger.info("#{@log_tag} Logo for project: #{project.slug} has not changed.")
        false

      _ ->
        latest_cmc_data
        |> LatestCoinmarketcapData.changeset(%{logo_hash: file_hash, logo_updated_at: Timex.now()})
        |> Repo.insert_or_update!()

        Logger.info("#{@log_tag} Logo for project: #{project.slug} has changed.")

        true
    end
  end

  defp resize_image(source_filepath, dest_dir_path, filename) do
    dest_filepath = dest_dir_path <> "/" <> filename

    Mogrify.open(source_filepath)
    |> Mogrify.resize("#{@size}x#{@size}")
    |> Mogrify.save(path: dest_filepath)

    {:ok, dest_filepath}
  end

  defp download(url, dir_path, filename) do
    filepath = Path.join(dir_path, filename)

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info("#{@log_tag} Successfully downloaded logo: #{url}")
        File.write!(filepath, body)
        {:ok, filepath}

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = "#{@log_tag} Failed downloading logo: #{url}. Status: #{status}"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = inspect(error)
        Logger.error("#{@log_tag} Error downloading logo: #{url}. Error message: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp upload(filepath) do
    with {:ok, filename} <- FileStore.store({filepath, "logo#{@size}"}) do
      Logger.info("#{@log_tag} Successfully uploaded logo from #{filepath} to: #{filename}")
      {:ok, FileStore.url({filename, "logo#{@size}"})}
    else
      {:error, error} ->
        error_msg = inspect(error)

        Logger.error(
          "#{@log_tag} Failed uploading logo: #{filepath}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end

  defp update_local_project(%Project{} = project, %{} = fields) do
    Project.changeset(project, fields) |> Repo.update()
  end
end
