defmodule FinancialAdvisorAi.Memory.EmailEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "email_embeddings" do
    field :email_id, :string
    field :subject, :string
    field :from_email, :string
    field :to_email, :string
    field :body, :string
    field :date, :utc_datetime
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(email_embedding, attrs) do
    email_embedding
    |> cast(attrs, [:email_id, :subject, :from_email, :to_email, :body, :date, :embedding, :user_id])
    |> validate_required([:email_id, :user_id])
  end
end
