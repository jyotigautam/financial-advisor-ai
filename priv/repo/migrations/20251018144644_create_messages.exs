defmodule FinancialAdvisorAi.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, null: false  # "user", "assistant", "system"
      add :content, :text, null: false
      add :tool_calls, :jsonb  # Store tool calling data
      add :metadata, :map  # Additional metadata

      timestamps()
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:conversation_id, :inserted_at])
  end
end
