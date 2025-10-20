defmodule FinancialAdvisorAi.Repo.Migrations.CreateContactEmbeddings do
  use Ecto.Migration

  def change do
    create table(:contact_embeddings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :contact_id, :string, null: false  # HubSpot contact ID
      add :email, :string
      add :name, :string
      add :notes, :text
      add :properties, :jsonb  # All HubSpot contact properties
      add :embedding, :vector, size: 1536  # OpenAI ada-002 embedding size

      timestamps()
    end

    create index(:contact_embeddings, [:user_id])
    create index(:contact_embeddings, [:contact_id])
    create index(:contact_embeddings, [:user_id, :email])
  end
end
