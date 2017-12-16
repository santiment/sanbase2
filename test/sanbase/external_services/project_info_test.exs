defmodule Sanbase.ExternalServices.ProjectInfoTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo

  test "updating project info if there is no ico attached to it" do
    project = %Project{coinmarketcap_id: "santiment", name: "Santiment"}
    |> Repo.insert!

    {:ok, project} = ProjectInfo.update_project(%ProjectInfo{
      name: "Santiment",
      coinmarketcap_id: "santiment",
      github_link: "https://github.com/santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
      contract_block_number: 3972935
    }, project)

    assert project.github_link == "https://github.com/santiment"
    assert Project.initial_ico(project).main_contract_address == "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    assert Project.initial_ico(project).contract_block_number == 3972935
  end

  test "updating project info if there is ico attached to it" do
    project = %Project{coinmarketcap_id: "santiment", name: "Santiment"}
    |> Repo.insert!

    ico = %Ico{project_id: project.id}
    |> Repo.insert!

    {:ok, project} = ProjectInfo.update_project(%ProjectInfo{
      name: "Santiment",
      coinmarketcap_id: "santiment",
      github_link: "https://github.com/santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
      contract_block_number: 3972935
    }, project)

    assert project.github_link == "https://github.com/santiment"
    assert Project.initial_ico(project).id == ico.id
    assert Project.initial_ico(project).main_contract_address == "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    assert Project.initial_ico(project).contract_block_number == 3972935
  end
end
