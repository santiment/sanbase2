defmodule Sanbase.Project.Description do
  @moduledoc false
  alias Sanbase.Project

  @spec describe(%Project{}) :: String.t()
  def describe(%Project{slug: cmc_id}) when not is_nil(cmc_id) do
    "project with slug: #{cmc_id}"
  end

  def describe(%Project{id: id}) do
    "project with id: #{id}"
  end
end
