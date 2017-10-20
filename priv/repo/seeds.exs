# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Sanbase.Repo.insert!(%Sanbase.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Sanbase.Model.Project
alias Sanbase.Model.ProjectBtcAddress
alias Sanbase.Model.ProjectEthAddress
alias Sanbase.Repo

[
  %Project{ticker: "ANT", name: "Aragon", coinmarketcap_id: "aragon"},
  %Project{ticker: "CFI", name: "Cofound.it", coinmarketcap_id: "cofound-it"},
  %Project{ticker: "DNA", name: "Encrypgen", coinmarketcap_id: nil},
  %Project{ticker: "SAN", name: "Santiment", coinmarketcap_id: "santiment"},
  %Project{ticker: "SNT", name: "Status.im", coinmarketcap_id: "status"},
]
|> Enum.each(&Repo.insert!/1)

[
  %ProjectEthAddress{
    project: Repo.get_by(Project, name: "Aragon"),
    address: "0xcafe1a77e84698c83ca8931f54a755176ef75f2c"
  },
  %ProjectEthAddress{
    project: Repo.get_by(Project, name: "Encrypgen"),
    address: "0x683a0aafa039406c104d814b9f244eea721445a7"
  },
  %ProjectEthAddress{
    project: Repo.get_by(Project, name: "Santiment"),
    address: "0x6dd5a9f47cfbc44c04a0a4452f0ba792ebfbcc9a"
  },
  %ProjectEthAddress{
    project: Repo.get_by(Project, name: "Status.im"),
    address: "0xA646E29877d52B9e2De457ECa09C724fF16D0a2B"
  },
]
|> Enum.each(&Repo.insert!/1)

[
  %ProjectBtcAddress{
    project: Repo.get_by(Project, name: "Encrypgen"),
    address: "13MoQt2n9cHNzbpt8PfeVYp2cehgzRgj6v"
  },
  %ProjectBtcAddress{
    project: Repo.get_by(Project, name: "Encrypgen"),
    address: "16bv1XAqh1YadAWHgDWgxKuhhns7T2EywG"
  },
  %ProjectBtcAddress{
    project: Repo.get_by(Project, name: "Encrypgen"),
    address: "3PtQX3dKbUb7Q8LguBrWVcwddf2yCkDJW9"
  },
  %ProjectBtcAddress{
    project: Repo.get_by(Project, name: "Encrypgen"),
    address: "33TK711ktEUJxERdTtkoE5cTaPVsi3JDya"
  },
  %ProjectBtcAddress{
    project: Repo.get_by(Project, name: "Encrypgen"),
    address: "3BnvD37EBj9EN89wrruPV44KxpYrYKTfQB"
  },
]
|> Enum.each(&Repo.insert!/1)
