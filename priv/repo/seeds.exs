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

Sanbase.Repo.insert!(%Sanbase.Item{name: "Milk"})
Sanbase.Repo.insert!(%Sanbase.Item{name: "Butter"})
Sanbase.Repo.insert!(%Sanbase.Item{name: "Bread"})
