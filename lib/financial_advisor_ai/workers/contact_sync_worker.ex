defmodule FinancialAdvisorAi.Workers.ContactSyncWorker do
  @moduledoc """
  Background worker to sync HubSpot contacts and create embeddings.
  Runs periodically for each user to keep contact data up to date.
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 3

  require Logger

  alias FinancialAdvisorAi.Accounts
  alias FinancialAdvisorAi.Integrations.HubspotClient
  alias FinancialAdvisorAi.Memory.Embedder
  alias FinancialAdvisorAi.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    Logger.info("Starting contact sync for user #{user_id}")

    user = Accounts.get_user!(user_id)

    if !user.hubspot_access_token do
      Logger.warning("User #{user_id} has no HubSpot token, skipping sync")
      {:ok, :skipped}
    else
      case HubspotClient.get_all_contacts(user) do
        {:ok, contacts} ->
          Logger.info("Synced #{length(contacts)} contacts for user #{user_id}")

          # Create embeddings for contacts
          synced_count = Enum.reduce(contacts, 0, fn contact, count ->
            case store_contact_with_embedding(user.id, contact) do
              {:ok, _} -> count + 1
              {:error, reason} ->
                Logger.error("Failed to store contact #{contact.id}: #{inspect(reason)}")
                count
            end
          end)

          Logger.info("Created #{synced_count} contact embeddings for user #{user_id}")

          {:ok, %{contacts_synced: length(contacts), embeddings_created: synced_count}}

        {:error, reason} ->
          Logger.error("Contact sync failed for user #{user_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Enqueue contact sync job for a user.
  """
  def enqueue_sync(user_id) do
    %{args: %{user_id: user_id}}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule recurring contact sync for a user.
  """
  def schedule_recurring_sync(user_id, interval_minutes \\ 60) do
    %{args: %{user_id: user_id}}
    |> __MODULE__.new(schedule_in: {interval_minutes, :minutes})
    |> Oban.insert()
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp store_contact_with_embedding(user_id, contact) do
    # Check if contact already exists
    existing = Repo.get_by(FinancialAdvisorAi.Memory.ContactEmbedding, contact_id: contact.id)

    if existing do
      # Update existing contact
      update_contact_embedding(existing, contact)
    else
      # Create new contact embedding
      contact_data = %{
        id: contact.id,
        email: contact.email || "",
        name: contact.name || "",
        notes: build_contact_notes(contact),
        properties: contact.properties || %{}
      }

      Embedder.store_contact_embedding(user_id, contact_data)
    end
  end

  defp update_contact_embedding(existing, contact) do
    # For now, just return ok. Could implement update logic if needed
    {:ok, existing}
  end

  defp build_contact_notes(contact) do
    # Combine various fields into searchable notes
    parts = [
      contact.notes,
      "Company: #{contact.company}",
      "Title: #{contact.jobtitle}",
      "Location: #{contact.city}, #{contact.state}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(". ")

    parts
  end
end
