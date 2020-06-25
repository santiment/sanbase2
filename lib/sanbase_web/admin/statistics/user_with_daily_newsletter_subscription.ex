defmodule SanbaseWeb.ExAdmin.Statistics.UsersWithDailyNewsletterSubscription do
  use ExAdmin.Register

  register_page "UsersWithDailyNewsletterSubscription" do
    menu(priority: 1, label: "UsersWithDailyNewsletterSubscription")

    content do
      h2 do
        div("Users with Daily Newsletter subscription")
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
      end

      users =
        Sanbase.Auth.Settings.daily_subscription_type()
        |> Sanbase.Auth.Statistics.newsletter_subscribed_users()

      users
      |> Enum.map(fn user ->
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
          end
        end
      end)

      h4 do
        div("-----------------------------")
        br()
        div("Comma separated list of the emails")
      end

      users |> Enum.map(& &1.email) |> Enum.reject(&is_nil/1) |> Enum.join(",")
    end
  end
end
