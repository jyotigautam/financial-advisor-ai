defmodule FinancialAdvisorAi.Repo.Migrations.FixEmbeddingDimensions do
  use Ecto.Migration

  def up do
    # Alter email_embeddings to use 768 dimensions (Gemini text-embedding-004)
    execute "ALTER TABLE email_embeddings ALTER COLUMN embedding TYPE vector(768);"

    # Alter contact_embeddings to use 768 dimensions
    execute "ALTER TABLE contact_embeddings ALTER COLUMN embedding TYPE vector(768);"
  end

  def down do
    # Revert back to 1536 dimensions
    execute "ALTER TABLE email_embeddings ALTER COLUMN embedding TYPE vector(1536);"
    execute "ALTER TABLE contact_embeddings ALTER COLUMN embedding TYPE vector(1536);"
  end
end
