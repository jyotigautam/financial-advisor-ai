defmodule FinancialAdvisorAi.Repo.Migrations.CreateOngoingInstructions do
  use Ecto.Migration

  def change do
    create table(:ongoing_instructions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :trigger_type, :string, null: false  # "email_received", "calendar_event_created", "hubspot_contact_created", etc.
      add :active, :boolean, default: true

      timestamps()
    end

    create index(:ongoing_instructions, [:user_id])
    create index(:ongoing_instructions, [:user_id, :active])
    create index(:ongoing_instructions, [:trigger_type, :active])
  end
end
