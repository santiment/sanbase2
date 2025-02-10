defmodule Sanbase.Repo.Migrations.AddLangPromoCoupons do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN
      CREATE TYPE public.lang AS ENUM ('en', 'jp');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """)

    alter table(:promo_coupons) do
      add(:lang, :lang)
    end
  end

  def down do
    alter table(:promo_coupons) do
      remove(:lang)
    end

    LangEnum.drop_type()
  end
end
