defmodule Sanbase.DirectAvailableSlugs do
  @behaviour Sanbase.AvailableSlugs.Behaviour

  @moduledoc ~s"""
  Direclty check the database if the slug is available. This module is used in
  tests where there are a lot of project inserts and the cached slugs are outdated.
  """
  @impl Sanbase.AvailableSlugs.Behaviour
  def valid_slug?(slug) do
    Sanbase.Model.Project.id_by_slug(slug) != nil
  end
end
