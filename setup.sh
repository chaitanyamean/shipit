#!/bin/bash
# ═══════════════════════════════════════════════════════════
# ShipIt — One-Time Setup Script
# ═══════════════════════════════════════════════════════════
#
# This script handles everything:
#   1. Collects your tokens
#   2. Collects your projects (no code editing needed)
#   3. Sets all Cloudflare Worker secrets
#   4. Deploys the Worker
#   5. Sets the Telegram webhook
#
# Prerequisites:
#   - Node.js installed (node + npm)
#   - A Telegram bot token from @BotFather
#   - A GitHub Personal Access Token (repo + workflow scopes)
#   - Your Telegram user ID (message @userinfobot to get it)

set -e

echo ""
echo "═══════════════════════════════════════════════"
echo "  🚀 ShipIt — Setup"
echo "═══════════════════════════════════════════════"
echo ""

# ─── Check Prerequisites ────────────────────────────────
if ! command -v npx &> /dev/null; then
  echo "❌ npx not found. Install Node.js first: https://nodejs.org"
  exit 1
fi

if ! npx wrangler --version &> /dev/null 2>&1; then
  echo "📦 Installing Wrangler..."
  npm install -g wrangler
fi

# ─── Collect Tokens ──────────────────────────────────────
echo "Step 1 of 3: Your tokens"
echo "────────────────────────"
echo ""
read -p "📱 Telegram Bot Token (from @BotFather): " TELEGRAM_BOT_TOKEN
echo ""
read -p "👤 Your Telegram User ID (from @userinfobot): " ALLOWED_TELEGRAM_USER_ID
echo ""
read -p "🔑 GitHub PAT with repo + workflow scopes: " GITHUB_PAT
echo ""

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$ALLOWED_TELEGRAM_USER_ID" ] || [ -z "$GITHUB_PAT" ]; then
  echo "❌ All three values are required."
  exit 1
fi

# ─── Collect Projects ────────────────────────────────────
echo ""
echo "Step 2 of 3: Your projects"
echo "──────────────────────────"
echo ""
echo "Add the GitHub repos you want to deploy from."
echo "The last project you add becomes the default."
echo ""

PROJECTS_STR=""
PROJECT_NUM=1

while true; do
  echo "── Project #${PROJECT_NUM} ──"
  read -p "  Project name (e.g. portfolio): " PROJ_NAME

  if [ -z "$PROJ_NAME" ]; then
    if [ $PROJECT_NUM -eq 1 ]; then
      echo "❌ You need at least one project."
      continue
    fi
    break
  fi

  read -p "  GitHub repo (e.g. yourname/my-site): " PROJ_REPO

  if [ -z "$PROJ_REPO" ]; then
    echo "  ❌ Repo is required. Try again."
    continue
  fi

  # Default keywords = project name
  read -p "  Keywords to detect this project [${PROJ_NAME}]: " PROJ_KEYWORDS
  PROJ_KEYWORDS=${PROJ_KEYWORDS:-$PROJ_NAME}

  # Build the string
  if [ -n "$PROJECTS_STR" ]; then
    PROJECTS_STR="${PROJECTS_STR}|"
  fi
  PROJECTS_STR="${PROJECTS_STR}${PROJ_NAME}:${PROJ_REPO}:${PROJ_KEYWORDS}"

  echo "  ✅ Added: ${PROJ_NAME} → ${PROJ_REPO}"
  echo ""

  PROJECT_NUM=$((PROJECT_NUM + 1))
  read -p "Add another project? (y/N): " ADD_MORE
  echo ""
  if [ "$ADD_MORE" != "y" ] && [ "$ADD_MORE" != "Y" ]; then
    break
  fi
done

echo ""
echo "Projects configured: $PROJECTS_STR"
echo ""

# ─── Set Secrets & Deploy ────────────────────────────────
echo "Step 3 of 3: Deploy"
echo "───────────────────"
echo ""
echo "📡 Setting Cloudflare Worker secrets..."

cd "$(dirname "$0")/../cloudflare-worker"

echo "$TELEGRAM_BOT_TOKEN" | npx wrangler secret put TELEGRAM_BOT_TOKEN
echo "$ALLOWED_TELEGRAM_USER_ID" | npx wrangler secret put ALLOWED_TELEGRAM_USER_ID
echo "$GITHUB_PAT" | npx wrangler secret put GITHUB_PAT
echo "$PROJECTS_STR" | npx wrangler secret put PROJECTS

echo "✅ All secrets set"

echo ""
echo "🚀 Deploying Cloudflare Worker..."
DEPLOY_OUTPUT=$(npx wrangler deploy 2>&1)
echo "$DEPLOY_OUTPUT"

WORKER_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[^ ]+\.workers\.dev' | head -1)

if [ -z "$WORKER_URL" ]; then
  echo ""
  echo "⚠️  Could not detect Worker URL automatically."
  read -p "📡 Paste your Worker URL (e.g. https://shipit-bot.xxx.workers.dev): " WORKER_URL
fi

echo "✅ Worker deployed: $WORKER_URL"

# ─── Set Telegram Webhook ────────────────────────────────
echo ""
echo "🔗 Setting Telegram webhook..."
WEBHOOK_RESULT=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook?url=${WORKER_URL}")
echo "   $WEBHOOK_RESULT"

# ─── Verify ──────────────────────────────────────────────
echo ""
echo "🔍 Verifying..."
VERIFY=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo" | grep -o '"url":"[^"]*"')
echo "   Webhook: $VERIFY"

cd ..

# ─── Done ────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ Setup Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "  Worker URL:  $WORKER_URL"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Copy .github/workflows/telegram-devops.yml"
echo "     into each project repo you want to deploy."
echo ""
echo "  2. Add these GitHub Secrets to each project repo"
echo "     (Settings → Secrets → Actions):"
echo ""
echo "     ANTHROPIC_API_KEY    — from console.anthropic.com"
echo "     TELEGRAM_BOT_TOKEN   — (already entered above)"
echo "     GITHUB_PAT           — (already entered above)"
echo "     VERCEL_TOKEN          — from vercel.com/account/tokens"
echo "     VERCEL_ORG_ID         — from .vercel/project.json"
echo "     VERCEL_PROJECT_ID     — from .vercel/project.json"
echo ""
echo "  3. Send a message to your bot on Telegram!"
echo ""
