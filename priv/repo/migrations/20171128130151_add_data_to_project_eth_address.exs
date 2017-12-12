defmodule Sanbase.Repo.Migrations.AddDataToProjectEthAddress do
  use Ecto.Migration
  require Logger
  alias Sanbase.Model.Project
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Repo

  def make_eth_address({name, address}) do
    [
      %ProjectEthAddress{
        project: Repo.get_by(Project, name: name),
        address: address
      }
    ]
  end

  def store(%ProjectEthAddress{} = project_eth_address) do
    case Repo.get_by(ProjectEthAddress, address: project_eth_address.address) do
      nil -> Repo.insert!(project_eth_address)
      %ProjectEthAddress{} = result->
        Logger.info("Address #{project_eth_address.address} already in ProjectEthAddress table.")
    end
  end

  def change do
    [
      {"Etherisc", "0x35792029777427920ce7aDecccE9e645465e9C72"},
      {"Musiconomi", "0xc7CD9d874F93F2409F39A95987b3E3C738313925"},
      {"Encrypgen", "0x683a0aafa039406c104d814b9f244eea721445a7"}
    ]
    |> Enum.flat_map(&make_eth_address/1)
    |> Enum.each(&store/1)
  end

end
