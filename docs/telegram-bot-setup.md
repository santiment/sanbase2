## Sanbase Telegram Bot Setup

1. To create a new telegram bot, you need to use the chat API of BotFather. You can start a chat [here](https://telegram.me/botfather).

2. Send the `/newbot` command and then you will be asked for a display name and a username. That's it, now you will be sent an access token.

3. Add the following to `config/dev.secret.exs`:

```elixir
import Config

config :sanbase, Sanbase.Telegram,
  name: "your_bot_name_here",
  bot_username: "your_bot_username_here",
  link: "t.me/your_bot_username_here",
  token: "your_access_token_here"
```

4. You need to have authentication setup and be able to login on `localhost:4000/auth/google`.

5. Now get your telegram link trough graphiql:
```graphql
{
  getTelegramDeepLink
}
```

6. Go to the link you got from the query result, press send message and that should navigate you to Telegram and send the /start command.

7. You should be able to manually send messages to yourself trough the bot now.
```elixir
User.by_email("your_sanbase@email.here") |> Repo.preload(:user_settings) |> Sanbase.Telegram.send_message("hello there")
```
