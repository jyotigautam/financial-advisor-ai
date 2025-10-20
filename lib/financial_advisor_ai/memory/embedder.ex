defmodule FinancialAdvisorAi.Memory.Embedder do
  @moduledoc """
  Generates embeddings for text using various providers.
  Supports Gemini (FREE!), OpenAI, and local models.
  """

  require Logger

  @doc """
  Generate an embedding vector for the given text.

  Returns {:ok, vector} where vector is a list of floats.
  """
  def embed(text) when is_binary(text) do
    provider = Application.get_env(:financial_advisor_ai, :llm_provider, "gemini")

    case provider do
      "gemini" -> embed_gemini(text)
      "openai" -> embed_openai(text)
      _ -> {:error, "Embeddings not supported for provider: #{provider}"}
    end
  end

  @doc """
  Embed multiple texts in a single batch (more efficient).
  """
  def embed_batch(texts) when is_list(texts) do
    provider = Application.get_env(:financial_advisor_ai, :llm_provider, "gemini")

    case provider do
      "gemini" -> embed_batch_gemini(texts)
      "openai" -> embed_batch_openai(texts)
      _ -> {:error, "Batch embeddings not supported for provider: #{provider}"}
    end
  end

  # ============================================================================
  # GEMINI EMBEDDINGS (FREE!)
  # ============================================================================

  defp embed_gemini(text) do
    api_key = Application.get_env(:financial_advisor_ai, :gemini_api_key)
    model = Application.get_env(:financial_advisor_ai, :gemini_embedding_model, "text-embedding-004")

    if !api_key do
      {:error, "GEMINI_API_KEY not set"}
    else
      url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:embedContent?key=#{api_key}"

      body = %{
        content: %{
          parts: [%{text: text}]
        }
      }

      case Req.post(url, json: body) do
        {:ok, %{status: 200, body: response}} ->
          embedding = response["embedding"]["values"]
          {:ok, embedding}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Gemini embedding error: #{status} - #{inspect(body)}")
          {:error, "Gemini API returned status #{status}"}

        {:error, reason} ->
          Logger.error("Gemini embedding request failed: #{inspect(reason)}")
          {:error, "Failed to generate embedding: #{inspect(reason)}"}
      end
    end
  end

  defp embed_batch_gemini(texts) do
    api_key = Application.get_env(:financial_advisor_ai, :gemini_api_key)
    model = Application.get_env(:financial_advisor_ai, :gemini_embedding_model, "text-embedding-004")

    if !api_key do
      {:error, "GEMINI_API_KEY not set"}
    else
      url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:batchEmbedContents?key=#{api_key}"

      requests = Enum.map(texts, fn text ->
        %{
          content: %{
            parts: [%{text: text}]
          }
        }
      end)

      body = %{requests: requests}

      case Req.post(url, json: body) do
        {:ok, %{status: 200, body: response}} ->
          embeddings = Enum.map(response["embeddings"], & &1["values"])
          {:ok, embeddings}

        {:ok, %{status: status, body: body}} ->
          {:error, "Gemini batch embedding error: #{status} - #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Failed to generate batch embeddings: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # OPENAI EMBEDDINGS
  # ============================================================================

  defp embed_openai(text) do
    api_key = Application.get_env(:financial_advisor_ai, :openai_api_key)
    model = Application.get_env(:financial_advisor_ai, :openai_embedding_model, "text-embedding-3-small")

    if !api_key do
      {:error, "OPENAI_API_KEY not set"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        input: text,
        model: model
      }

      case Req.post("https://api.openai.com/v1/embeddings", json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          embedding = response["data"] |> List.first() |> Map.get("embedding")
          {:ok, embedding}

        {:ok, %{status: status, body: body}} ->
          {:error, "OpenAI embedding error: #{status} - #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Failed to generate embedding: #{inspect(reason)}"}
      end
    end
  end

  defp embed_batch_openai(texts) do
    api_key = Application.get_env(:financial_advisor_ai, :openai_api_key)
    model = Application.get_env(:financial_advisor_ai, :openai_embedding_model, "text-embedding-3-small")

    if !api_key do
      {:error, "OPENAI_API_KEY not set"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        input: texts,
        model: model
      }

      case Req.post("https://api.openai.com/v1/embeddings", json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          embeddings = Enum.map(response["data"], & &1["embedding"])
          {:ok, embeddings}

        {:ok, %{status: status, body: body}} ->
          {:error, "OpenAI batch embedding error: #{status} - #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Failed to generate batch embeddings: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp truncate_text(nil, _max_bytes), do: ""
  defp truncate_text(text, max_bytes) when is_binary(text) do
    if byte_size(text) <= max_bytes do
      text
    else
      # Truncate to max_bytes and add indicator
      binary_part(text, 0, max_bytes) <> "\n\n[Email truncated for embedding...]"
    end
  end

  @doc """
  Store an email with its embedding in the database.
  """
  def store_email_embedding(user_id, email_data) do
    alias FinancialAdvisorAi.Repo
    alias FinancialAdvisorAi.Memory.EmailEmbedding

    # Truncate body to avoid Gemini 36KB limit (keep ~10KB for embedding to be safe)
    truncated_body = truncate_text(email_data.body, 10_000)

    # Create text to embed from email (this is what goes to Gemini)
    text = """
    Subject: #{email_data.subject}
    From: #{email_data.from}
    To: #{email_data.to}
    Date: #{email_data.date}

    #{truncated_body}
    """

    case embed(text) do
      {:ok, embedding} ->
        %EmailEmbedding{}
        |> EmailEmbedding.changeset(%{
          user_id: user_id,
          email_id: email_data.id,
          subject: email_data.subject,
          from_email: email_data.from,
          to_email: email_data.to,
          body: truncated_body,  # Store truncated version
          date: email_data.date,
          embedding: embedding
        })
        |> Repo.insert()

      error -> error
    end
  end

  @doc """
  Store a HubSpot contact with its embedding.
  """
  def store_contact_embedding(user_id, contact_data) do
    alias FinancialAdvisorAi.Repo
    alias FinancialAdvisorAi.Memory.ContactEmbedding

    # Create text to embed from contact
    text = """
    Name: #{contact_data.name}
    Email: #{contact_data.email}
    Notes: #{contact_data.notes}
    #{format_properties(contact_data.properties)}
    """

    case embed(text) do
      {:ok, embedding} ->
        %ContactEmbedding{}
        |> ContactEmbedding.changeset(%{
          user_id: user_id,
          contact_id: contact_data.id,
          email: contact_data.email,
          name: contact_data.name,
          notes: contact_data.notes,
          properties: contact_data.properties,
          embedding: embedding
        })
        |> Repo.insert()

      error -> error
    end
  end

  defp format_properties(nil), do: ""
  defp format_properties(props) when is_map(props) do
    props
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join("\n")
  end
end
