defmodule Sanbase.Repo.Migrations.ResetWeeklyNewsletterSetting do
  use Ecto.Migration

  @moduledoc """
  The weekly newsletter setting defaulted to on and was never connected to a
  Mailjet list, so it shows on for most users without them ever opting in.
  It starts from the marketing consent (users.marketing_accepted), which
  includes the newsletter. The mirrored is_subscribed_marketing_emails setting
  is aligned too.

  This only rewrites the stored settings. It does not call Mailjet. After the
  deploy, Sanbase.Email.ListImport.import_from_mailjet(:newsletter) makes the
  setting match the Mailjet list.
  """

  def up() do
    execute("""
    UPDATE user_settings us
    SET settings = COALESCE(us.settings, '{}'::jsonb) || jsonb_build_object(
          'is_subscribed_weekly_newsletter', u.marketing_accepted,
          'is_subscribed_marketing_emails', u.marketing_accepted
        ),
        updated_at = NOW()
    FROM users u
    WHERE u.id = us.user_id
    """)

    # Users without a settings row would get the new default (off), which is
    # wrong for those who accepted marketing.
    execute("""
    INSERT INTO user_settings (user_id, settings, inserted_at, updated_at)
    SELECT u.id,
           jsonb_build_object(
             'is_subscribed_weekly_newsletter', true,
             'is_subscribed_marketing_emails', true
           ),
           NOW(),
           NOW()
    FROM users u
    WHERE u.marketing_accepted
      AND NOT EXISTS (SELECT 1 FROM user_settings us WHERE us.user_id = u.id)
    """)
  end

  # The previous values were a default, not a user's choice, so there is
  # nothing to restore.
  def down(), do: :ok
end
