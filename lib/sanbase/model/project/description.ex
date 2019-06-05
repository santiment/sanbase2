defmodule Sanbase.Model.Project.Description do
  alias Sanbase.Model.Project

  @spec describe(%Project{}) :: String.t()
  def describe(%Project{coinmarketcap_id: cmc_id}) when not is_nil(cmc_id) do
    "project with slug: #{cmc_id}"
  end

  def describe(%Project{id: id}) do
    "project with id: #{id}"
  end
end
