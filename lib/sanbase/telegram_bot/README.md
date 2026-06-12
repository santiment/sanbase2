# Telegram Q&A Bot (Santiment AI)

Telegram analogue of the Discord Q&A bot (`lib/sanbase/discord_bot/`). Users ask
questions in a group by mentioning the bot; follow-ups continue via reply chains,
mirroring the Discord "thread" UX. **Group-only — private messages are ignored.**

This README is self-contained: it carries all the context needed to work on this
code without re-reading the Discord bot or re-doing the research.

## Background / architecture context

How the existing Discord bot works (and what we mirror):

- **The AI lives in an external service**, not in this repo. `Sanbase.DiscordBot.AiServer`
  POSTs to `#{AI_SERVER_URL}/question` with
  `%{question, messages, route_blacklist, metadata}` and gets back
  `%{"answer" => %{"answer", "sources", "tokens_*", "total_cost", "prompt"}, "route", "function_called"}`.
  `messages` is OpenAI-style history: `[%{role: "user"|"assistant", content: ...}]`.
- **Context = DB, not platform.** Every Q&A pair is stored in the `ai_context`
  Postgres table keyed by `thread_id`. Before each question,
  `AiContext.fetch_history_context(metadata, 10)` loads the last 10 Q&A pairs for
  that `thread_id` and sends them as `messages`. Same conversation id → context
  continues; new conversation id → fresh context.
- **Rate limits**: `AiContext.check_limits/1` — 10 questions/day per `guild_id` for
  non-pro, 20 for pro (counted on rows with `command == "!ai"`, which the AI server's
  `route` determines). On limit, the "twitter" route is blacklisted.
- Discord-specific transport: Nostrum gateway consumer, auto thread creation,
  👍/👎 buttons writing into `ai_context.votes`.

What this Telegram bot reuses **unchanged**:

- `Sanbase.DiscordBot.AiServer.answer/2` (the metadata map just gets Telegram-flavored values)
- `Sanbase.DiscordBot.AiContext` — persistence, history context, votes, rate limits
- `Sanbase.DiscordBot.Utils.split_message/2`
- `Sanbase.TaskSupervisor` (from `Sanbase.Application.common_children/0`)

`ai_context` needs **no schema change**: its columns are plain strings, so Telegram
IDs are namespaced with a `tg_` prefix (no collision with Discord snowflakes).
Required changeset fields (`discord_user, guild_id, channel_id, question`) are all
provided; unknown keys are ignored by `cast`.

The **one DB addition** is `telegram_bot_messages` (chat_id, message_id,
conversation_id): Telegram's `reply_to_message` is only one level deep, so reply
chains cannot be walked from an update alone. Every answer message the bot sends
is recorded there; when a user replies to a bot message, the replied-to id is
looked up to find which conversation to continue.

**Existing, unrelated Telegram code** (do not confuse / do not touch):
`Sanbase.Telegram` (`lib/sanbase/telegram/telegram.ex`) is the *alerts* bot — Tesla
client, token `TELEGRAM_SIGNALS_BOT_TOKEN`, webhook route `/telegram/:path`
(`SanbaseWeb.TelegramController`). This Q&A bot uses a **different BotFather bot**
and **long-polling**, so the two never compete for updates.

## Modules

| File | Module | Role |
|---|---|---|
| `api.ex` | `Sanbase.TelegramBot.Api` | Thin HTTPoison client for the Telegram Bot API (`getMe`, `getUpdates`, `sendMessage`, `sendChatAction`, `createForumTopic`, `answerCallbackQuery`, `editMessageReplyMarkup`, `deleteWebhook`). Token from `TELEGRAM_QA_BOT_TOKEN`. `enabled?/0` gates startup. |
| `poller.ex` | `Sanbase.TelegramBot.Poller` | GenServer long-polling loop: `deleteWebhook` → `getMe` (bot id/username) → `getUpdates` (30s long poll, offset tracking). Each update is handled in a `Task.Supervisor` task so slow AI calls never block polling. Errors back off 5s; `getMe` failure retries every 30s. |
| `message_handler.ex` | `Sanbase.TelegramBot.MessageHandler` | All UX logic: triggers, conversation mapping, AI call, replies, votes. |
| `bot_message.ex` | `Sanbase.TelegramBot.BotMessage` | `telegram_bot_messages` schema: maps sent bot messages to conversation ids for reply-chain continuation. |

Supervision: `lib/sanbase/application/queries.ex` starts the Poller via
`start_if(fn -> Sanbase.TelegramBot.Poller end, fn -> Api.enabled?() end)` —
**same pod as the Discord bot (queries)**. Deploy = set `TELEGRAM_QA_BOT_TOKEN`
(+ existing `AI_SERVER_URL`) on the queries pod; without the env var the bot
simply doesn't start anywhere else. Note: `children_opts("all")` in
`application.ex` had a copy-paste bug (queries children taken from
`Admin.children()`) fixed on this branch — before that fix, neither the Discord
nor the Telegram bot started under `CONTAINER_TYPE=all` (the local default).

## UX / conversation model

Group-only. DMs get a static redirect ("I only answer in the Santiment group");
messages from other bots are ignored. In groups, two triggers:

1. **`@mention <question>`** → starts a **new conversation**, bot answers as a
   reply to the question message.
2. **Replying to any bot answer** → **continues** that conversation (no mention
   needed). This is the Discord-thread analogue: same chain = context, fresh
   mention = clean slate.

Conversation id (= `ai_context.thread_id`) mapping — this is what scopes context:

| Surface | `thread_id` | Behavior |
|---|---|---|
| Plain group, new mention | `tg_<chat_id>_m<message_id>` | New reply-chain conversation rooted at the question message. |
| Plain group, reply to a bot answer | looked up in `telegram_bot_messages` | Continues the chain's conversation. Unknown bot message (pre-tracking) → new conversation. |
| Forum supergroup, message inside a topic (`is_topic_message`) | `tg_<chat_id>_<topic_id>` | Per-topic context (works if a community prefers forum layout). |
| Forum supergroup, mention in General | `tg_<chat_id>_<new_topic_id>` | Bot creates a topic (needs admin + *Manage Topics*), echoes the question, answers there. Falls back to a reply-chain conversation if topic creation fails. |

Reply-chains are the **primary** model (recommended for `@santiment_network` —
no forum-mode conversion of the group needed); the topic path is kept for
forum-enabled groups.

Rate limiting falls out of the reuse: `guild_id` is set to `tg_<chat_id>`, so the
existing per-guild counters become **per-Telegram-chat** (10/day, since
`user_is_pro` is always `false` — there is no Telegram↔Sanbase account link yet;
pro-gating would be a separate account-linking project).

Replies:

- "typing…" chat action every 5s while the AI server call runs (it can take ~1-4 min;
  HTTP timeout in `AiServer` is 240s).
- Answer + sources, split at 4000 chars (Telegram hard limit 4096).
- Sent with `parse_mode: Markdown`, **falling back to plain text** on 400 (Telegram's
  legacy Markdown parser rejects unbalanced `*`/`_`, which LLM output often contains).
- Every sent chunk is recorded in `telegram_bot_messages` (replying to any chunk
  continues the conversation).
- Last chunk carries an inline keyboard 👍/👎 with `callback_data` `up_<ai_context_id>` /
  `down_<ai_context_id>`; presses update `ai_context.votes` (`%{"tg:<user>" => 1|-1}`)
  and edit the button labels with the new counts — same data model as Discord.

## Environment variables

| Var | Purpose |
|---|---|
| `TELEGRAM_QA_BOT_TOKEN` | Token of the Q&A bot from BotFather. **Must NOT be the alerts bot token** (`TELEGRAM_SIGNALS_BOT_TOKEN`) — one Telegram token can only have one updates consumer. Unset = bot disabled. |
| `AI_SERVER_URL` | Already used by the Discord bot. Point to local/staging AI server in dev. |

## Local testing guide

1. **Create a dev bot**: in Telegram, talk to `@BotFather` → `/newbot` → pick a name
   and username (e.g. `santiment_ai_dev_bot`). Copy the token.
2. **Configure the test group**:
   - Create a group, add the bot.
   - Make the bot **admin** (no permission toggles needed for reply-chains; admin
     bypasses privacy mode so the bot sees plain `@mentions`). Alternative to
     admin: BotFather → `/setprivacy` → Disable.
   - For reply-chain testing keep **Topics OFF**. (Topics ON exercises the
     forum-topic path instead — then the bot also needs the *Manage Topics*
     admin permission.)
3. **Migrate + run**:
   ```sh
   mix ecto.migrate

   TELEGRAM_QA_BOT_TOKEN="123456:ABC..." \
   AI_SERVER_URL="http://localhost:8000" \
   iex -S mix phx.server
   ```
   Expect log: `[TelegramQABot] starting to poll as @<bot_username>`.
4. **Test the conversation model**:
   - `@<bot> <question>` → typing… → answer as a reply, with 👍/👎 buttons.
   - **Reply to the answer** with a follow-up (no mention) → contextual answer.
   - New `@<bot> <question>` → fresh context (no bleed from the first chain).
   - Press 👍 → button label updates to `👍 1`.
5. **Inspect persistence**:
   ```sql
   select thread_id, question, command, votes from ai_context order by id desc limit 10;
   select * from telegram_bot_messages order by id desc limit 10;
   ```

Gotchas:

- `getUpdates` returns **409 Conflict** if another process polls the same token
  (e.g. a second local node) or a webhook is set. The Poller calls `deleteWebhook`
  at startup; make sure only one node runs with the token.
- Daily limit is 10 questions/chat (non-pro); during heavy testing you may hit it —
  it resets at midnight UTC, or delete today's `ai_context` rows for your chat.

## Future work (deliberately out of scope for the pilot)

- Product-owner decisions for `@santiment_network`: budget/limits, disclaimer text,
  launch scope.
- Pro-gating → requires Telegram↔Sanbase account linking (deep-link auth, like the
  alerts bot's `/start <token>` flow).
- Webhook transport for prod (reuse a Phoenix route) instead of long-polling — optional;
  polling is fine at pilot scale.
- `platform` column + generic `conversation_id` on `ai_context` instead of `tg_` prefixes.
- Cleanup/TTL for `telegram_bot_messages` rows if volume ever warrants it.
