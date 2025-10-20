defmodule FinancialAdvisorAi.Memory.ContactEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_embeddings" do
    field :contact_id, :string
    field :email, :string
    field :name, :string
    field :notes, :string
    field :properties, :map
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(contact_embedding, attrs) do
    contact_embedding
    |> cast(attrs, [:contact_id, :email, :name, :notes, :properties, :embedding, :user_id])
    |> validate_required([:contact_id, :user_id])
  end
end
