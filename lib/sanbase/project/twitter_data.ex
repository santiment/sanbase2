defmodule Sanbase.Project.TwitterData do
  alias Sanbase.Project

  def twitter_handle(%Project{twitter_link: nil} = project),
    do: {:error, "Missing twitter link for #{Project.describe(project)}"}

  def twitter_handle(%Project{twitter_link: "https://twitter.com/" <> twitter_name} = project) do
    case String.split(twitter_name, "/") |> hd do
      "" -> {:error, "Malformed twitter link for #{Project.describe(project)}"}
      name -> {:ok, name}
    end
  end

  def twitter_handle(%Project{} = project),
    do: {:error, "Malformed twitter link for #{Project.describe(project)}"}
end
