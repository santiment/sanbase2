defmodule SanbaseWeb.GenericAdmin.Project do
  import Ecto.Query

  def schema_module, do: Sanbase.Project

  def resource() do
    %{
      preloads: [:infrastructure],
      index_fields: [
        :id,
        :ticker,
        :name,
        :slug,
        :website_link,
        :infrastructure_id,
        :token_decimals,
        :is_hidden
      ],
      new_fields: [
        :name,
        :ticker,
        :slug,
        :description,
        :long_description,
        :token_supply,
        :infrastructure,
        :token_decimals,
        :is_hidden,
        :telegram_chat_id,
        :logo_url,
        :dark_logo_url,
        :email,
        :blog_link,
        :btt_link,
        :facebook_link,
        :linkedin_link,
        :reddit_link,
        :slack_link,
        :discord_link,
        :telegram_link,
        :twitter_link,
        :website_link,
        :whitepaper_link
      ],
      belongs_to_fields: %{
        infrastructure:
          from(i in Sanbase.Model.Infrastructure, order_by: i.code)
          |> Sanbase.Repo.all()
          |> Enum.map(&{&1.code, &1.id})
      },
      edit_fields: [
        :name,
        :ticker,
        :slug,
        :description,
        :long_description,
        :token_supply,
        :infrastructure,
        :token_decimals,
        :is_hidden,
        :telegram_chat_id,
        :logo_url,
        :dark_logo_url,
        :email,
        :blog_link,
        :btt_link,
        :facebook_link,
        :linkedin_link,
        :reddit_link,
        :slack_link,
        :discord_link,
        :telegram_link,
        :twitter_link,
        :website_link,
        :whitepaper_link
      ],
      funcs: %{
        infrastructure_id: &__MODULE__.link/1
      }
    }
  end

  def link(row) do
    if row.infrastructure do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "infrastructures",
        row.infrastructure.id,
        row.infrastructure.code
      )
    end
  end
end

defmodule SanbaseWeb.GenericAdmin.Infrastructure do
  def schema_module, do: Sanbase.Model.Infrastructure

  def resource() do
    %{
      new_fields: [:code],
      edit_fields: [:code]
    }
  end
end
