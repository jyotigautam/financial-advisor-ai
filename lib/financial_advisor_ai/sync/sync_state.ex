defmodule FinancialAdvisorAi.Sync.SyncState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_state" do
    field :service, :string
    field :last_sync_token, :string
    field :last_synced_at, :utc_datetime

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(sync_state, attrs) do
    sync_state
    |> cast(attrs, [:service, :last_sync_token, :last_synced_at, :user_id])
    |> validate_required([:service, :user_id])
    |> validate_inclusion(:service, ["gmail", "calendar", "hubspot"])
    |> unique_constraint([:user_id, :service])
  end
end
