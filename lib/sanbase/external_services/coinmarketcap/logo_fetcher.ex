defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.Model.{Project, LatestCoinmarketcapData}
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo
  alias Sanbase.FileStore
  alias Sanbase.Utils.FileHash

  @log_tag "[CMC][LogoFetcher]"
  @size 64

  def run() do
    projects = Project.List.projects_with_source("coinmarketcap", include_hidden: true)

    local_projects_map =
      projects
      |> Enum.map(fn %{slug: slug} = project -> {slug, project} end)
      |> Map.new()

    Logger.info("#{@log_tag} Started fetching logos from coinmarketcap.")

    Temp.track!()
    dir_path = Temp.mkdir!("logos")

    projects
    |> Enum.chunk_every(100)
    |> Enum.each(fn projects ->
      {:ok, remote_projects} = CryptocurrencyInfo.fetch_data(projects)

      Enum.each(remote_projects, fn remote_project ->
        update_project_logos(remote_project, local_projects_map, dir_path)
      end)
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
             {_, true} <- {:logo_has_changed?, logo_changed?(project, local_filepath)},
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
    coinmarketcap_id = Project.coinmarketcap_id(project)

    case coinmarketcap_id && LatestCoinmarketcapData.get_or_build(coinmarketcap_id) do
      nil ->
        false

      latest_cmc_data ->
        {:ok, file_hash} = FileHash.calculate(filepath)

        case {latest_cmc_data.logo_hash, project.logo_url} do
          {^file_hash, nil} ->
            Logger.info("#{@log_tag} Logo for project: #{project.slug} has changed.")
            true

          {^file_hash, _} ->
            Logger.info("#{@log_tag} Logo for project: #{project.slug} has not changed.")
            false

          {_, _} ->
            latest_cmc_data
            |> LatestCoinmarketcapData.changeset(%{
              logo_hash: file_hash,
              logo_updated_at: Timex.now()
            })
            |> Repo.insert_or_update!()

            Logger.info("#{@log_tag} Logo for project: #{project.slug} has changed.")

            true
        end
    end
  end

  defp resize_image(source_filepath, dest_dir_path, filename) do
    dest_filepath = dest_dir_path <> "/" <> filename

    Mogrify.open(source_filepath)
    |> Mogrify.resize("#{@size}x#{@size}")
    |> Mogrify.custom("type", "PaletteAlpha")
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
    case FileStore.store({filepath, "logo#{@size}"}) do
      {:ok, filename} ->
        Logger.info("#{@log_tag} Successfully uploaded logo from #{filepath} to: #{filename}")
        {:ok, FileStore.url({filename, "logo#{@size}"})}

      {:error, error} ->
        error_msg = inspect(error)

        Logger.error(
          "#{@log_tag} Failed uploading logo: #{filepath}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end

  defp update_local_project(%Project{} = project, %{} = fields) do
    case Project.changeset(project, fields) |> Repo.update() do
      {:ok, schema} ->
        {:ok, schema}

      {:error, error} ->
        error_msg = changeset_errors_string(error)

        Logger.error(
          "#{@log_tag} Error updating project locally: #{project.slug}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end
end
