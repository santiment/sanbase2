defmodule Sanbase.Repo.Migrations.AddLangPromoCoupons do
  use Ecto.Migration

  def up do
    LangEnum.create_type()

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
