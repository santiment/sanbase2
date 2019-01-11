defmodule Sanbase.ExAdmin.ScheduleRescrapePrice do
  use ExAdmin.Register

  register_resource Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice do
    form srp do
      inputs do
        input(srp, :from, type: NaiveDateTime)
        input(srp, :to, type: NaiveDateTime)
        input(srp, :original_last_updated, type: NaiveDateTime)

        input(
          srp,
          :project,
          collection: from(p in Sanbase.Model.Project, order_by: p.name) |> Sanbase.Repo.all()
        )
      end
    end
  end
end
