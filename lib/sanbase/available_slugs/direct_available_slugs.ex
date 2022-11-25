defmodule Sanbase.DirectAvailableSlugs do
  @moduledoc ~s"""
  Direclty check the database if the slug is available. This module is used in
  tests where there are a lot of project inserts and the cached slugs are outdated.
  """
  @behaviour Sanbase.AvailableSlugs.Behaviour

  @impl Sanbase.AvailableSlugs.Behaviour
  def valid_slug?(slug) do
    Sanbase.Project.id_by_slug(slug) != nil
  end
end
