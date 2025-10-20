defmodule FinancialAdvisorAi.DataSync do
  @moduledoc """
  Service for syncing external data (Gmail, HubSpot) into the database with embeddings.
  This enables RAG (Retrieval Augmented Generation) for AI responses.

  ## How it works:

  1. User authenticates via OAuth (Google/HubSpot)
  2. Call `sync_all_data(user)` to fetch and embed data
  3. Data is stored in email_embeddings and contact_embeddings tables
  4. AI Agent uses Memory.Search to find relevant data via vector similarity
  5. Gemini uses that context to answer user questions

  ## Example:

      # After OAuth:
      user = Accounts.get_user!(user_id)
      DataSync.sync_all_data(user)

      # Now AI can answer:
      # "Find emails about baseball" -> RAG searches embeddings
      # "Show me contacts from Acme Corp" -> RAG searches contacts
  """

  require Logger

  alias FinancialAdvisorAi.Accounts.User
  alias FinancialAdvisorAi.Workers.{EmailSyncWorker, ContactSyncWorker}

  @doc """
  Sync all data sources for a user (Gmail + HubSpot).
  This will:
  1. Fetch recent emails from Gmail
  2. Fetch contacts from HubSpot
  3. Generate embeddings for all data
  4. Store in database for RAG search

  Returns a summary of synced data.
  """
  def sync_all_data(%User{} = user) do
    Logger.info("Starting full data sync for user #{user.id}")

    results = %{
      emails: sync_emails(user),
      contacts: sync_contacts(user)
    }

    Logger.info("Full sync complete for user #{user.id}: #{inspect(results)}")
    {:ok, results}
  end

  @doc """
  Sync only Gmail emails for a user.

  Options:
  - :days_back - Number of days to sync (default: 7)
  - :async - If true, enqueue background job instead of running now
  """
  def sync_emails(%User{} = user, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    days_back = Keyword.get(opts, :days_back, 7)

    if !user.google_access_token do
      Logger.warning("User #{user.id} has no Google OAuth token. Cannot sync emails.")
      {:error, :no_google_token}
    else
      if async do
        Logger.info("Enqueueing async email sync for user #{user.id}")
        EmailSyncWorker.enqueue_sync(user.id, days_back: days_back)
      else
        Logger.info("Running immediate email sync for user #{user.id}")
        # Run synchronously
        case EmailSyncWorker.perform(%Oban.Job{args: %{"user_id" => user.id, "days_back" => days_back}}) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Sync only HubSpot contacts for a user.

  Options:
  - :async - If true, enqueue background job instead of running now
  """
  def sync_contacts(%User{} = user, opts \\ []) do
    async = Keyword.get(opts, :async, false)

    if !user.hubspot_access_token do
      Logger.warning("User #{user.id} has no HubSpot OAuth token. Cannot sync contacts.")
      {:error, :no_hubspot_token}
    else
      if async do
        Logger.info("Enqueueing async contact sync for user #{user.id}")
        ContactSyncWorker.enqueue_sync(user.id)
      else
        Logger.info("Running immediate contact sync for user #{user.id}")
        # Run synchronously
        case ContactSyncWorker.perform(%Oban.Job{args: %{"user_id" => user.id}}) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Schedule recurring background sync for a user.
  This will automatically sync data periodically.

  Options:
  - :email_interval_minutes - How often to sync emails (default: 30)
  - :contact_interval_minutes - How often to sync contacts (default: 60)
  """
  def schedule_recurring_sync(%User{} = user, opts \\ []) do
    email_interval = Keyword.get(opts, :email_interval_minutes, 30)
    contact_interval = Keyword.get(opts, :contact_interval_minutes, 60)

    results = []

    results = if user.google_access_token do
      case EmailSyncWorker.schedule_recurring_sync(user.id, email_interval) do
        {:ok, _job} ->
          Logger.info("Scheduled recurring email sync for user #{user.id} every #{email_interval} minutes")
          [{:email_sync, :scheduled} | results]
        {:error, reason} ->
          Logger.error("Failed to schedule email sync: #{inspect(reason)}")
          [{:email_sync, {:error, reason}} | results]
      end
    else
      [{:email_sync, :no_token} | results]
    end

    results = if user.hubspot_access_token do
      case ContactSyncWorker.schedule_recurring_sync(user.id, contact_interval) do
        {:ok, _job} ->
          Logger.info("Scheduled recurring contact sync for user #{user.id} every #{contact_interval} minutes")
          [{:contact_sync, :scheduled} | results]
        {:error, reason} ->
          Logger.error("Failed to schedule contact sync: #{inspect(reason)}")
          [{:contact_sync, {:error, reason}} | results]
      end
    else
      [{:contact_sync, :no_token} | results]
    end

    {:ok, results}
  end

  @doc """
  Get sync status for a user.
  Shows what data sources are connected and when last synced.
  """
  def get_sync_status(%User{} = user) do
    alias FinancialAdvisorAi.Repo
    alias FinancialAdvisorAi.Memory.{EmailEmbedding, ContactEmbedding}
    import Ecto.Query

    # Count embedded emails
    email_count = Repo.one(
      from e in EmailEmbedding,
      where: e.user_id == ^user.id,
      select: count(e.id)
    )

    # Count embedded contacts
    contact_count = Repo.one(
      from c in ContactEmbedding,
      where: c.user_id == ^user.id,
      select: count(c.id)
    )

    # Get last sync times
    last_email_sync = Repo.one(
      from e in EmailEmbedding,
      where: e.user_id == ^user.id,
      select: max(e.inserted_at)
    )

    last_contact_sync = Repo.one(
      from c in ContactEmbedding,
      where: c.user_id == ^user.id,
      select: max(c.inserted_at)
    )

    %{
      google_connected: !is_nil(user.google_access_token),
      hubspot_connected: !is_nil(user.hubspot_access_token),
      emails_count: email_count,
      contacts_count: contact_count,
      last_email_sync: last_email_sync,
      last_contact_sync: last_contact_sync
    }
  end
end
