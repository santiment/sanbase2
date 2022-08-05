defmodule SanbaseWeb.Graphql.Resolvers.DiscordResolver do
  alias Sanbase.Notifications.Discord.Bot

  def add_to_pro_role_in_discord(_root, args, %{
        context: %{auth: %{subscription: subscription, plan: plan}}
      }) do
    case subscription.status == :active and plan in ["PRO", "PRO_PLUS"] do
      true -> Bot.add_pro_role(args.discord_username)
      false -> {:error, "Please, upgrade to Sanbase PRO plan or higher!"}
    end
  end
end
