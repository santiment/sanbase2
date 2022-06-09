defmodule Sanbase.Repo.Migrations.UpdateFinishedPriceRescrapes do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  def up do
    setup()

    # The code that updated the is_progress to false had a typo - the last `s`
    # was missing so the field was not properly updated. The rescrapes cannot be
    # both finished and in_progress - if it is finished, then update the in_progress
    # to false

    from(
      srp in ScheduleRescrapePrice,
      where: srp.finished == true and srp.in_progress == true
    )
    |> Sanbase.Repo.update_all(set: [in_progress: false])
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
