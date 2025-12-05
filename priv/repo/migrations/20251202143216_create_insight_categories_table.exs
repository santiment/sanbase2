defmodule Sanbase.Repo.Migrations.CreateInsightCategoriesTable do
  use Ecto.Migration

  def change do
    create table(:insight_categories) do
      add(:name, :string, null: false)
      add(:description, :text)

      timestamps()
    end

    create(unique_index(:insight_categories, [:name]))

    # Seed the 5 predefined categories
    execute("""
    INSERT INTO insight_categories (name, description, inserted_at, updated_at) VALUES
      ('On-chain market analysis', 'An insight that analyzes crypto markets based on network activity or wallet behavior on an asset''s blockchain', NOW(), NOW()),
      ('Social Trends market analysis', 'An insight that analyzes crypto markets based on discussion and discourse trends and activity across social media', NOW(), NOW()),
      ('Education on using Santiment', 'An article or video that provides information and context about how to use a webpage, product, or service provided by Santiment', NOW(), NOW()),
      ('Product launch/update', 'An article or video that shows off a new, revised, or updated feature that is provided by Santiment', NOW(), NOW()),
      ('Promotional discount/sale', 'An article or video that announces or reminds readers about a promotion, discount, or sale for a Santiment product or service', NOW(), NOW())
    """)
  end
end
