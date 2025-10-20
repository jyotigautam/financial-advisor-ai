# AI Financial Advisor 🤖💼

A production-ready AI assistant for financial advisors. Built with Elixir/Phoenix, powered by Google Gemini.

**What it does:** Helps financial advisors search emails, manage calendars, track contacts, and automate tasks using natural language.

## ✨ Features

- 🧠 **Real AI** - Google Gemini 1.5 Flash (FREE: 15 req/min, 1500/day)
- 🔍 **RAG Search** - Semantic search across emails & contacts using pgvector
- 📧 **Gmail** - Read, search, send emails
- 📅 **Calendar** - View, create, manage events
- 👥 **HubSpot CRM** - Contacts, companies, deals
- 🛠️ **10 Tools** - AI can call functions to automate tasks
- ⚡ **Real-time UI** - Phoenix LiveView chat interface
- 🔄 **Background Jobs** - Auto-sync with Oban workers
- 🔗 **Webhooks** - Proactive responses to external events

## 🚀 Quick Start

### Step 1: Get Gemini API Key (FREE)
```bash
# Visit https://makersuite.google.com/app/apikey
# Click "Create API Key" and copy it
```

### Step 2: Setup Google OAuth
```bash
# 1. Visit https://console.cloud.google.com/apis/credentials
# 2. Create OAuth 2.0 Client ID
# 3. Add redirect URI: http://localhost:4000/auth/google/callback
# 4. Enable Gmail API and Calendar API
# 5. Add test user: webshookeng@gmail.com
# 6. Copy Client ID and Client Secret
```

### Step 3: Setup HubSpot OAuth
```bash
# 1. Visit https://developers.hubspot.com/
# 2. Create app
# 3. Add redirect URI: http://localhost:4000/auth/hubspot/callback
# 4. Add scopes: crm.objects.contacts.read, crm.objects.contacts.write
# 5. Copy Client ID and Client Secret
```

### Step 4: Configure & Run
```bash
# Edit .env.example with your keys
nano .env.example

# Add:
# GEMINI_API_KEY="your_key"
# GOOGLE_CLIENT_ID="your_id"
# GOOGLE_CLIENT_SECRET="your_secret"
# HUBSPOT_CLIENT_ID="your_id"
# HUBSPOT_CLIENT_SECRET="your_secret"

# Run the app
source .env.example && iex -S mix phx.server

# Visit http://localhost:4000/chat
```

## 📊 Sync Your Data (Required for RAG)

After connecting OAuth, sync your Gmail and HubSpot data:

**Option 1: Use the Chat UI**
1. Visit http://localhost:4000/chat
2. Click "Sync Gmail" and "Sync HubSpot" in the blue status bar
3. Wait ~1 minute for data to sync and embed

**Option 2: Use IEx Console**
```elixir
user = FinancialAdvisorAi.Accounts.get_user_by_email("webshookeng@gmail.com")
FinancialAdvisorAi.DataSync.sync_all_data(user)
```

**What happens:** Fetches emails/contacts → generates embeddings → stores in database → enables RAG search

📖 **See [DATA_SYNC_GUIDE.md](DATA_SYNC_GUIDE.md) for complete sync documentation**

## 🎯 Try These Queries

Once data is synced, try these in http://localhost:4000/chat:

**RAG Email Search (semantic search):**
- "Find emails about baseball"
- "Show me emails from Bill"
- "Search emails mentioning project proposal"

**RAG Contact Search:**
- "Find contacts from Acme Corporation"
- "Who are my contacts in finance?"

**AI Actions:**
- "Send an email to john@example.com saying thanks"
- "Schedule a meeting tomorrow at 2pm with Bill"
- "Create a HubSpot contact for jane@company.com"

## ✅ What's Included

All production code is **already generated and ready**:

- ✅ LLM Client (Gemini + OpenAI + Claude + Ollama)
- ✅ RAG System (embeddings + vector search)
- ✅ OAuth (Google + HubSpot)
- ✅ Gmail Integration
- ✅ Calendar Integration
- ✅ HubSpot CRM Integration
- ✅ AI Agent with tool calling
- ✅ 10 working tools
- ✅ Background workers (Oban)
- ✅ Webhook handlers
- ✅ Chat UI (LiveView)

## 📁 Project Structure

```
lib/financial_advisor_ai/
├── ai/
│   ├── llm_client.ex        # Gemini + OpenAI + Claude + Ollama
│   ├── agent.ex              # Main AI orchestrator
│   └── tool_registry.ex      # 10 callable tools
├── integrations/
│   ├── gmail_client.ex       # Gmail API client
│   ├── calendar_client.ex    # Google Calendar client
│   └── hubspot_client.ex     # HubSpot CRM client
├── memory/
│   ├── embedder.ex           # Generate embeddings (Gemini)
│   └── search.ex             # Vector search (RAG)
└── workers/
    ├── email_sync_worker.ex  # Background email sync
    └── contact_sync_worker.ex # Background contact sync

lib/financial_advisor_ai_web/
├── controllers/
│   ├── auth_controller.ex    # OAuth (Google + HubSpot)
│   └── webhook_controller.ex # Webhook handlers
└── live/
    └── chat_live.ex          # Chat UI (LiveView)
```

## 🔐 Connect OAuth

After starting the server, connect your accounts:

```bash
# 1. Google (Gmail + Calendar)
open http://localhost:4000/auth/google

# 2. HubSpot (CRM)
open http://localhost:4000/auth/hubspot/authorize
```

Grant permissions when prompted. Now the AI can access your real data!

## 💰 Costs

**FREE Development:**
- Gemini: 15 req/min, 1500/day (FREE!)
- Embeddings: Unlimited (FREE!)
- PostgreSQL: Local (FREE!)

**Production (~$12/month):**
- Gemini: ~$0.10/day
- Database: ~$7/month
- Hosting: ~$5/month

## 🏗️ Architecture

```
User → ChatLive → Agent → LLM (Gemini)
                     ↓
           ┌─────────────┬──────────────┐
           │ RAG Search  │ Tool Calling │
           │ (pgvector)  │ (10 tools)   │
           └─────────────┴──────────────┘
                ↓                ↓
           Embeddings      Gmail/Calendar
                           HubSpot APIs
```

## 🛠️ Tech Stack

- **Elixir 1.15+** / **Phoenix 1.8**
- **PostgreSQL 15+** with pgvector
- **Google Gemini 1.5 Flash** (LLM)
- **Phoenix LiveView** (UI)
- **Oban 2.18** (background jobs)
- **Ueberauth** (OAuth)

## 🐛 Troubleshooting

**"GEMINI_API_KEY not set"**
- Make sure you edited `.env.example` with your actual key
- Run `source .env.example` before `iex -S mix phx.server`

**Database errors**
```bash
brew services start postgresql@15
mix ecto.migrate
```

## 📄 License

MIT

---

**Built with ❤️ using Elixir, Phoenix, and Google Gemini**
