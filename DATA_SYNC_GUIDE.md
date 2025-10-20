# Data Sync & RAG Guide

This guide explains how to fetch Gmail/HubSpot data, store it in the database with embeddings, and enable AI to answer questions using RAG (Retrieval Augmented Generation).

## 🎯 How It Works

```
User Question → AI Agent → RAG Search (vector similarity) → Find relevant emails/contacts → Gemini answers with context
```

## 📋 Step-by-Step Setup

### Step 1: Connect OAuth Accounts

**Connect Google (for Gmail & Calendar):**
```bash
# Start the server
source .env.example && iex -S mix phx.server

# Visit in browser:
open http://localhost:4000/auth/google
```

Grant permissions when prompted. This stores OAuth tokens in the database.

**Connect HubSpot (for CRM contacts):**
```bash
# Visit in browser:
open http://localhost:4000/auth/hubspot/authorize
```

Grant CRM permissions.

### Step 2: Sync Data

**Option A: From the Chat UI**

1. Go to http://localhost:4000/chat
2. Look at the blue "Data Status" bar at the top
3. Click "Sync Gmail" or "Sync HubSpot" buttons
4. Wait 30-60 seconds for sync to complete

**Option B: From IEx Console**

```elixir
# Get your user
user = FinancialAdvisorAi.Accounts.get_user_by_email("webshookeng@gmail.com")

# Sync all data (Gmail + HubSpot)
FinancialAdvisorAi.DataSync.sync_all_data(user)

# Or sync individually:
FinancialAdvisorAi.DataSync.sync_emails(user)        # Gmail only
FinancialAdvisorAi.DataSync.sync_contacts(user)     # HubSpot only

# Check sync status:
FinancialAdvisorAi.DataSync.get_sync_status(user)
```

### Step 3: What Happens During Sync

**For Gmail Emails:**
1. Fetches last 30 days of emails via Gmail API
2. For each email:
   - Extracts subject, from, to, body, date
   - Creates embedding vector (768 dimensions) using Gemini
   - Stores in `email_embeddings` table with user_id
3. Emails are now searchable by semantic meaning!

**For HubSpot Contacts:**
1. Fetches all contacts via HubSpot API
2. For each contact:
   - Extracts name, email, company, notes, properties
   - Creates embedding vector using Gemini
   - Stores in `contact_embeddings` table with user_id
3. Contacts are now searchable by semantic meaning!

### Step 4: Test RAG Search

**Try these queries in the chat:**

```
"Find emails about baseball"
→ AI searches email_embeddings using vector similarity
→ Returns relevant emails even if they don't contain exact word "baseball"

"Show me emails from Bill"
→ RAG finds emails where from field matches "Bill"

"Find contacts from Acme Corporation"
→ Searches contact_embeddings for company name

"Who are my contacts in finance?"
→ Semantic search across contact notes and properties
```

## 🔧 Manual Sync Examples

### Sync Recent Emails Only

```elixir
user = FinancialAdvisorAi.Accounts.get_user!(user_id)

# Sync last 7 days only
FinancialAdvisorAi.DataSync.sync_emails(user, days_back: 7)

# Async (runs in background)
FinancialAdvisorAi.DataSync.sync_emails(user, async: true, days_back: 30)
```

### Schedule Recurring Sync

```elixir
user = FinancialAdvisorAi.Accounts.get_user!(user_id)

# Auto-sync every 30 minutes (emails) and 60 minutes (contacts)
FinancialAdvisorAi.DataSync.schedule_recurring_sync(user)

# Custom intervals
FinancialAdvisorAi.DataSync.schedule_recurring_sync(user,
  email_interval_minutes: 15,
  contact_interval_minutes: 30
)
```

## 🗄️ Database Schema

**email_embeddings table:**
```sql
id: UUID
user_id: UUID (foreign key to users)
email_id: String (Gmail message ID)
subject: String
from: String
to: String
body: Text
date: DateTime
embedding: vector(768)  -- Gemini embedding
inserted_at: DateTime
updated_at: DateTime
```

**contact_embeddings table:**
```sql
id: UUID
user_id: UUID (foreign key to users)
contact_id: String (HubSpot contact ID)
name: String
email: String
notes: Text
properties: JSONB
embedding: vector(768)  -- Gemini embedding
inserted_at: DateTime
updated_at: DateTime
```

## 🤖 How AI Uses RAG

When you ask a question, the AI Agent:

1. **Determines if RAG is needed** - Analyzes question intent
2. **Generates query embedding** - Converts question to vector
3. **Vector similarity search** - Finds top 5 most similar items using pgvector cosine distance
4. **Filters by threshold** - Only includes results with >0.7 similarity
5. **Adds to context** - Passes relevant emails/contacts to Gemini
6. **Gemini responds** - Answers question using the retrieved context

**Example flow:**

```
User: "Find emails about project proposal"
  ↓
Agent: Detects this needs email search
  ↓
Memory.Search.search_emails(user_id, "project proposal")
  ↓
pgvector finds emails with similar semantic meaning
  ↓
Agent formats emails as context:
  "Here are relevant emails:
   - From: john@acme.com, Subject: Q4 Proposal Draft
   - From: jane@startup.com, Subject: Proposal Review"
  ↓
Gemini receives context + user question → Responds intelligently
```

## 🔍 Vector Search Details

**Cosine Similarity Formula:**
```
similarity = 1 - (embedding1 <=> embedding2)
```

Where `<=>` is pgvector's cosine distance operator.

**Search query (from Memory.Search module):**
```elixir
query = from e in EmailEmbedding,
  where: e.user_id == ^user_id,
  select: %{
    email: e,
    similarity: fragment("1 - (? <=> ?)", e.embedding, ^query_embedding)
  },
  order_by: fragment("? <=> ?", e.embedding, ^query_embedding),
  limit: ^limit

results = Repo.all(query)
filtered = Enum.filter(results, fn %{similarity: sim} -> sim >= 0.7 end)
```

## 🚨 Troubleshooting

**"No Google token" error:**
```bash
# Re-authenticate:
open http://localhost:4000/auth/google
```

**"No HubSpot token" error:**
```bash
# Re-authenticate:
open http://localhost:4000/auth/hubspot/authorize
```

**Sync not working:**
```elixir
# Check user tokens:
user = FinancialAdvisorAi.Accounts.get_user!(user_id)
IO.inspect(user.google_access_token)  # Should not be nil
IO.inspect(user.hubspot_access_token)  # Should not be nil

# Check sync status:
FinancialAdvisorAi.DataSync.get_sync_status(user)
```

**No results from RAG search:**
```elixir
# Check if embeddings exist:
alias FinancialAdvisorAi.Repo
alias FinancialAdvisorAi.Memory.EmailEmbedding
import Ecto.Query

Repo.all(from e in EmailEmbedding, where: e.user_id == ^user_id, select: count(e.id))
# Should return > 0

# Test direct search:
alias FinancialAdvisorAi.Memory.Search
{:ok, results} = Search.search_emails(user_id, "test")
IO.inspect(results)
```

**Embeddings taking too long:**
- Gemini has rate limits: 15 requests/min (free tier)
- For 100 emails, expect ~7 minutes
- Use `async: true` to run in background
- Check Oban dashboard for job status

## 📊 Monitoring Sync Jobs

**Check Oban job queue:**
```elixir
# View pending jobs
alias FinancialAdvisorAi.Repo
import Ecto.Query

Repo.all(from j in Oban.Job, where: j.state == "available", select: j)

# View completed jobs
Repo.all(from j in Oban.Job, where: j.state == "completed", order_by: [desc: j.completed_at], limit: 10)

# View failed jobs
Repo.all(from j in Oban.Job, where: j.state == "retryable" or j.state == "discarded")
```

## 💡 Tips

1. **Initial sync takes time** - First sync of 100 emails = ~7 minutes due to Gemini rate limits
2. **Use async for large syncs** - Don't block the UI, run in background
3. **Schedule recurring sync** - Keep data fresh automatically
4. **Test with small dataset first** - Sync 7 days before syncing all data
5. **Monitor Oban jobs** - Check if sync jobs are completing successfully

## 🔗 Related Files

- `lib/financial_advisor_ai/data_sync.ex` - Main sync service
- `lib/financial_advisor_ai/workers/email_sync_worker.ex` - Email background worker
- `lib/financial_advisor_ai/workers/contact_sync_worker.ex` - Contact background worker
- `lib/financial_advisor_ai/memory/embedder.ex` - Embedding generation
- `lib/financial_advisor_ai/memory/search.ex` - RAG vector search
- `lib/financial_advisor_ai/ai/agent.ex` - AI orchestration with RAG
- `lib/financial_advisor_ai_web/live/chat_live.ex` - UI with sync controls
