defmodule FinancialAdvisorAi.Repo.Migrations.CreateEmailEmbeddings do
  use Ecto.Migration

  def change do
    create table(:email_embeddings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :email_id, :string, null: false  # Gmail message ID
      add :subject, :text
      add :from_email, :string
      add :to_email, :string
      add :body, :text
      add :date, :utc_datetime
      add :embedding, :vector, size: 1536  # OpenAI ada-002 embedding size

      timestamps()
    end

    create index(:email_embeddings, [:user_id])
    create index(:email_embeddings, [:email_id])
    create index(:email_embeddings, [:user_id, :date])
  end
end
