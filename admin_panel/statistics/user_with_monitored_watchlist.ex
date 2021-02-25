defmodule SanbaseWeb.ExAdmin.Statistics.UsersWithMonitoredWatchlist do
  use ExAdmin.Register

  register_page "UsersWithMonitoredWatchlist" do
    menu(priority: 1, label: "UsersWithMonitoredWatchlist")

    content do
      h2 do
        div("Users with monitored watchlist/watchlist weekly summary")
      end

      table do
        th do
          pre("| ID", style: "all: initial; margin: 0 10px 0 10px;")
        end

        th do
          pre("| email", style: "all: initial; margin: 0 10px 0 10px;")
        end

        th do
          pre("| username", style: "all: initial; margin: 0 10px 0 10px;")
        end

        th do
          pre("| watchlist count", style: "all: initial; margin: 0 10px 0 10px;")
        end
      end

      list =
        Sanbase.UserLists.Statistics.users_with_monitored_watchlist()
        |> Enum.sort_by(fn {_, count} -> count end, &>=/2)

      list
      |> Enum.map(fn {user, watchlist_count} ->
        p do
          tr do
            td do
              pre("| #{user.id}", style: "all: initial; margin: 0 10px 0 10px;")
            end

            td do
              pre("| #{user.email}", style: "all: initial; margin: 0 10px 0 10px;")
            end

            td do
              pre("| #{user.username}", style: "all: initial; margin: 0 10px 0 10px;")
            end

            td do
              pre("| #{watchlist_count}", style: "all: initial; margin: 0 10px 0 10px;")
            end
          end
        end
      end)

      h4 do
        div("-----------------------------")
        br()

        div(
          "Comma separated list of the emails. (those with missing emails are skipped from the list)"
        )
      end

      list
      |> Enum.reject(fn {user, _} -> is_nil(user.email) end)
      |> Enum.map(fn {user, _} -> user.email end)
      |> Enum.join(",")
    end
  end
end
