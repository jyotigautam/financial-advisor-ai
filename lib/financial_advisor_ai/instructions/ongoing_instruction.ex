defmodule FinancialAdvisorAi.Instructions.OngoingInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ongoing_instructions" do
    field :instruction, :string
    field :trigger_type, :string
    field :active, :boolean, default: true

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  @valid_triggers [
    "email_received",
    "email_sent",
    "calendar_event_created",
    "calendar_event_updated",
    "hubspot_contact_created",
    "hubspot_contact_updated",
    "any"
  ]

  @doc false
  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:instruction, :trigger_type, :active, :user_id])
    |> validate_required([:instruction, :trigger_type, :user_id])
    |> validate_inclusion(:trigger_type, @valid_triggers)
  end

  def valid_triggers, do: @valid_triggers
end
