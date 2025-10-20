defmodule FinancialAdvisorAi.Memory.Search do
  @moduledoc """
  Semantic search using pgvector for RAG (Retrieval Augmented Generation).
  Searches emails and contacts using cosine similarity on embeddings.
  """

  import Ecto.Query
  alias FinancialAdvisorAi.Repo
  alias FinancialAdvisorAi.Memory.{EmailEmbedding, ContactEmbedding, Embedder}

  @doc """
  Search emails semantically using vector similarity.

  Returns a list of relevant emails ranked by similarity score.

  ## Options
    * `:limit` - Maximum number of results (default: 5)
    * `:threshold` - Minimum similarity score 0-1 (default: 0.7)
    * `:from_date` - Filter emails after this date
    * `:to_date` - Filter emails before this date

  ## Examples

      iex> Search.search_emails(user_id, "baseball tickets")
      {:ok, [
        %{email: %EmailEmbedding{...}, similarity: 0.92},
        %{email: %EmailEmbedding{...}, similarity: 0.85}
      ]}
  """
  def search_emails(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.3)  # Lowered from 0.7 to be more permissive

    with {:ok, query_embedding} <- Embedder.embed(query_text) do
      # Build base query
      query = from e in EmailEmbedding,
        where: e.user_id == ^user_id,
        select: %{
          email: e,
          similarity: fragment("1 - (? <=> ?)", e.embedding, ^query_embedding)
        },
        order_by: fragment("? <=> ?", e.embedding, ^query_embedding),
        limit: ^limit

      # Add date filters if provided
      query = add_date_filters(query, opts)

      # Execute query
      results = Repo.all(query)

      # Filter by threshold
      filtered_results = Enum.filter(results, fn %{similarity: sim} -> sim >= threshold end)

      {:ok, filtered_results}
    end
  end

  @doc """
  Search HubSpot contacts semantically.

  Returns a list of relevant contacts ranked by similarity score.

  ## Options
    * `:limit` - Maximum number of results (default: 5)
    * `:threshold` - Minimum similarity score 0-1 (default: 0.7)

  ## Examples

      iex> Search.search_contacts(user_id, "real estate investors")
      {:ok, [
        %{contact: %ContactEmbedding{...}, similarity: 0.88},
        %{contact: %ContactEmbedding{...}, similarity: 0.81}
      ]}
  """
  def search_contacts(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.3)  # Lowered from 0.7 to be more permissive

    with {:ok, query_embedding} <- Embedder.embed(query_text) do
      query = from c in ContactEmbedding,
        where: c.user_id == ^user_id,
        select: %{
          contact: c,
          similarity: fragment("1 - (? <=> ?)", c.embedding, ^query_embedding)
        },
        order_by: fragment("? <=> ?", c.embedding, ^query_embedding),
        limit: ^limit

      results = Repo.all(query)
      filtered_results = Enum.filter(results, fn %{similarity: sim} -> sim >= threshold end)

      {:ok, filtered_results}
    end
  end

  @doc """
  Hybrid search: search both emails and contacts.

  Returns combined results from both sources.

  ## Examples

      iex> Search.search_all(user_id, "baseball")
      {:ok, %{
        emails: [...],
        contacts: [...]
      }}
  """
  def search_all(user_id, query_text, opts \\ []) do
    with {:ok, email_results} <- search_emails(user_id, query_text, opts),
         {:ok, contact_results} <- search_contacts(user_id, query_text, opts) do
      {:ok, %{
        emails: email_results,
        contacts: contact_results
      }}
    end
  end

  @doc """
  Find emails similar to a given email (for "more like this" functionality).
  """
  def find_similar_emails(email_embedding_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.7)

    case Repo.get(EmailEmbedding, email_embedding_id) do
      nil -> {:error, :not_found}

      source_email ->
        query = from e in EmailEmbedding,
          where: e.user_id == ^source_email.user_id,
          where: e.id != ^email_embedding_id,
          select: %{
            email: e,
            similarity: fragment("1 - (? <=> ?)", e.embedding, ^source_email.embedding)
          },
          order_by: fragment("? <=> ?", e.embedding, ^source_email.embedding),
          limit: ^limit

        results = Repo.all(query)
        filtered_results = Enum.filter(results, fn %{similarity: sim} -> sim >= threshold end)

        {:ok, filtered_results}
    end
  end

  @doc """
  Get context for RAG by searching relevant information.

  This is the main function used by the AI agent to retrieve context
  before generating responses.

  Returns formatted context string suitable for LLM prompt injection.

  ## Examples

      iex> Search.get_rag_context(user_id, "What did Bill say about baseball?")
      {:ok, "RELEVANT EMAILS:\\n1. Subject: Baseball tickets...\\n\\nRELEVANT CONTACTS:\\n..."}
  """
  def get_rag_context(user_id, query, opts \\ []) do
    email_limit = Keyword.get(opts, :email_limit, 3)
    contact_limit = Keyword.get(opts, :contact_limit, 3)

    with {:ok, results} <- search_all(user_id, query,
           limit: max(email_limit, contact_limit),
           threshold: Keyword.get(opts, :threshold, 0.3)) do

      # Format emails
      email_context = results.emails
      |> Enum.take(email_limit)
      |> Enum.with_index(1)
      |> Enum.map(fn {%{email: email, similarity: sim}, idx} ->
        """
        #{idx}. [Similarity: #{Float.round(sim, 2)}]
           Subject: #{email.subject}
           From: #{email.from_email}
           To: #{email.to_email}
           Date: #{format_date(email.date)}
           Body: #{String.slice(email.body, 0..300)}...
        """
      end)
      |> Enum.join("\n")

      # Format contacts
      contact_context = results.contacts
      |> Enum.take(contact_limit)
      |> Enum.with_index(1)
      |> Enum.map(fn {%{contact: contact, similarity: sim}, idx} ->
        """
        #{idx}. [Similarity: #{Float.round(sim, 2)}]
           Name: #{contact.name}
           Email: #{contact.email}
           Notes: #{contact.notes || "N/A"}
        """
      end)
      |> Enum.join("\n")

      context = """
      RELEVANT EMAILS:
      #{if email_context == "", do: "No relevant emails found.", else: email_context}

      RELEVANT CONTACTS:
      #{if contact_context == "", do: "No relevant contacts found.", else: contact_context}
      """

      {:ok, context}
    end
  end

  @doc """
  Check if RAG search would return useful results without actually performing the search.
  Useful for deciding whether to use RAG for a given query.
  """
  def would_rag_help?(user_id, query) do
    # Quick check: do we have any embeddings for this user?
    email_count = Repo.one(from e in EmailEmbedding,
      where: e.user_id == ^user_id,
      select: count(e.id))

    contact_count = Repo.one(from c in ContactEmbedding,
      where: c.user_id == ^user_id,
      select: count(c.id))

    total_count = email_count + contact_count

    cond do
      total_count == 0 -> {:ok, false}
      total_count < 5 -> {:ok, :maybe}  # Limited data
      true -> {:ok, true}
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp add_date_filters(query, opts) do
    query
    |> maybe_add_from_date(Keyword.get(opts, :from_date))
    |> maybe_add_to_date(Keyword.get(opts, :to_date))
  end

  defp maybe_add_from_date(query, nil), do: query
  defp maybe_add_from_date(query, from_date) do
    from e in query,
      where: e.date >= ^from_date
  end

  defp maybe_add_to_date(query, nil), do: query
  defp maybe_add_to_date(query, to_date) do
    from e in query,
      where: e.date <= ^to_date
  end

  defp format_date(nil), do: "N/A"
  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %I:%M %p")
  end
  defp format_date(date_string) when is_binary(date_string), do: date_string
end
