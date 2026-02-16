# ShipIt — Deploy from your phone. In plain English.

> I changed a button color on my live website. From my phone. While having chai.
> It took 90 seconds. No IDE. No terminal. No git commands. Just a Telegram message.

ShipIt is a serverless pipeline that connects **Telegram → Cloudflare Worker → GitHub Actions → Claude Code → auto-deploy**. You describe a code change in plain English, and it goes live.

```
You (Telegram):  "Add Docker to skills section in portfolio"

ShipIt:          🚀 Pipeline Triggered!
                 🧠 Claude Code analyzing...
                 ✅ Code changed — added Docker to skills array
                 ✅ Tests passed
                 📤 Pushed (a3f21bc)
                 🎉 Deployed to production!
```

**Total infrastructure cost: $0. Runs entirely on free tiers.**

---

## Why

Every developer maintaining websites knows this pain:

| What you want | What you actually do | Time |
|---|---|---|
| Fix a typo | Open IDE → find file → edit → save → commit → push → wait for CI → verify | 15 min |

ShipIt replaces the entire right column with a text message. The overhead isn't the change — it's the ceremony around it.

---

## How it works

```
┌──────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌────────┐
│ Telegram │────▶│ Cloudflare Worker│────▶│ GitHub Actions   │────▶│ Vercel │
│ message  │     │                  │     │                  │     │        │
│          │◀────│ • Auth           │     │ • Claude Code    │     │ Live!  │
│ You get  │     │ • Detect project │     │ • Run tests      │     │        │
│ notified │     │ • Dispatch       │     │ • Auto-fix       │     │        │
│ at each  │     │                  │     │ • Commit + push  │     │        │
│ step     │     │ Free tier ✓      │     │ Free tier ✓      │     │ Free ✓ │
└──────────┘     └──────────────────┘     └──────────────────┘     └────────┘
                  Always-on (0ms cold       Spins up on demand.
                  start). Only piece        Destroyed after.
                  that "runs".              Zero idle cost.
```

**Nothing is always-running except a Cloudflare Worker (free, 0ms cold start).** GitHub Actions runners spin up on demand and self-destruct. You pay only for Claude API calls (~$0.03 per change).

---

## What it can do

Works well for:
- Text and content changes ("fix the typo in about section")
- Adding/removing items ("add Kubernetes to skills")
- Style changes ("change the hero background to dark blue")
- Component tweaks ("make the contact button rounded")
- Config changes ("update the site title")
- Minor features ("add a tooltip to the email link")

Not designed for:
- Database schema changes
- Auth flows or third-party API integrations
- Major refactors or new pages from scratch
- Anything you'd want a code review for

---

## Setup (5 minutes)

You need: a Cloudflare account (free), a GitHub account, a Telegram account, and an Anthropic API key.

### Step 1: Create a Telegram bot (1 min)

Open Telegram, search for **@BotFather**, and send:

```
/newbot
```

Follow the prompts. You'll get a bot token like `7123456789:AAH...`. Save it.

Then get your Telegram user ID — send a message to **@userinfobot**. It replies with your numeric ID. Save it.

### Step 2: Create a GitHub Personal Access Token (1 min)

Go to [github.com/settings/tokens](https://github.com/settings/tokens) → **Generate new token (classic)**.

Select scopes: `repo` and `workflow`. Generate and save the token.

### Step 3: Deploy the Cloudflare Worker (2 min)

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/shipit.git
cd shipit

# Install Wrangler (Cloudflare CLI)
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Set secrets
cd cloudflare-worker
echo "YOUR_BOT_TOKEN" | npx wrangler secret put TELEGRAM_BOT_TOKEN
echo "YOUR_USER_ID" | npx wrangler secret put ALLOWED_TELEGRAM_USER_ID
echo "YOUR_GITHUB_PAT" | npx wrangler secret put GITHUB_PAT

# Deploy
npx wrangler deploy
```

Wrangler prints your Worker URL. It looks like:
`https://telegram-devops-bot.YOUR_SUBDOMAIN.workers.dev`

Now point Telegram at it:

```bash
curl "https://api.telegram.org/botYOUR_BOT_TOKEN/setWebhook?url=YOUR_WORKER_URL"
```

You should see `{"ok":true,"result":true}`.

### Step 4: Add the workflow to your project repo (1 min)

Copy `.github/workflows/telegram-devops.yml` into any repo you want to deploy from.

Then add these **GitHub Secrets** to that repo (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ANTHROPIC_API_KEY` | Your Claude API key from [console.anthropic.com](https://console.anthropic.com) |
| `TELEGRAM_BOT_TOKEN` | The bot token from Step 1 |
| `GITHUB_PAT` | The token from Step 2 |
| `VERCEL_TOKEN` | From [vercel.com/account/tokens](https://vercel.com/account/tokens) |
| `VERCEL_ORG_ID` | From `.vercel/project.json` in your project (run `vercel link` first) |
| `VERCEL_PROJECT_ID` | Same file as above |

### Step 5: Configure your projects

Set the PROJECTS secret with your repos. No code editing needed.

```bash
cd cloudflare-worker

# Format: name:owner/repo:keyword1,keyword2
# Multiple projects separated by |
echo "portfolio:your-username/your-portfolio:portfolio,my site|myapp:your-username/myapp:myapp" | npx wrangler secret put PROJECTS
```

That's it. The bot reads this at runtime to know which repos you have.

Redeploy: `npx wrangler deploy`

### Done. Send a message to your bot.

```
You: Add a "Hire me" badge to the hero section of portfolio
```

Watch the notifications roll in.

---

## Alternatively: run the setup script (recommended)

The setup script handles everything — tokens, projects, deploy, webhook — in one go:

```bash
cd scripts
chmod +x setup.sh
./setup.sh
```

It walks you through each step interactively. No code editing, no copy-pasting URLs.

---

## Multi-project routing

One bot handles all your projects. Just mention the project name in your message:

```
"Add Docker to skills in portfolio"       → pushes to portfolio repo
"Fix retry logic in myapp"                → pushes to myapp repo
"Change the button color to blue"         → pushes to default project
```

Add as many projects as you want to the `PROJECTS` secret. The bot matches keywords in your message to the project list. If no project is detected, it uses the last project as the default.

To add or change projects later:

```bash
cd cloudflare-worker
echo "portfolio:you/site:portfolio,my site|newproject:you/new:newproject" | npx wrangler secret put PROJECTS
```

---

## Deploy targets

The workflow ships with **Vercel** as the default deploy target. To use a different platform, edit `.github/workflows/telegram-devops.yml`:

**Netlify** — uncomment the Netlify section and add `NETLIFY_AUTH_TOKEN` + `NETLIFY_SITE_ID` as secrets.

**GitHub Pages** — uncomment the GitHub Pages section. No extra secrets needed.

**Cloudflare Pages** — add a Cloudflare Pages deploy step with your `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

---

## Architecture

```
Telegram (free)
  │
  │  Webhook POST (your message)
  ▼
Cloudflare Worker (free tier)
  │  • Authenticates you (checks Telegram user ID)
  │  • Detects which project you're talking about
  │  • Sends acknowledgment back to Telegram
  │
  │  repository_dispatch event
  ▼
GitHub Actions (2000 free min/month)
  │  • Checks out your repo
  │  • Runs Claude Code with your instruction
  │  • Runs your test suite
  │  • If tests fail → Claude Code auto-fixes → re-runs tests
  │  • If still failing → aborts and notifies you
  │  • If passing → commits, pushes
  │
  │  git push triggers deploy
  ▼
Vercel / Netlify / GitHub Pages (free tier)
  │  • Builds and deploys automatically
  │
  ▼
🎉 Your change is live
```

**Why these specific tools:**

| Tool | Why | Cost |
|---|---|---|
| Cloudflare Worker | 0ms cold start, runs at edge, generous free tier (100K requests/day) | Free |
| GitHub Actions | Built into GitHub, no extra service to manage, 2000 min/month free | Free |
| Claude Code | Best at understanding codebases and making targeted changes | ~$0.03/change |
| Vercel | Zero-config deploys for React/Next.js, instant rollbacks | Free |

---

## Cost breakdown

| Component | Monthly cost |
|---|---|
| Cloudflare Worker | $0 (free tier) |
| GitHub Actions | $0 (free tier covers ~500 deploys/month) |
| Claude API | ~$0.03 per change × your usage |
| Vercel | $0 (free tier) |
| **Total for 30 deploys/month** | **~$0.90** |

---

## Limitations

This is a v1 — intentionally simple. Here's what it doesn't do (yet):

- **No memory** — each change starts from scratch. The bot doesn't remember that your skills array is in `src/data/skills.ts`.
- **No planning** — complex multi-file changes sometimes fail because Claude tries to do everything in one shot.
- **No rollback command** — if something breaks, you'll need to `git revert` manually.
- **Single retry** — if tests fail, Claude gets one auto-fix attempt. After that, it aborts.
- **No web dashboard** — everything happens through Telegram.
- **Telegram only** — no Slack, Discord, or WhatsApp yet.

These are all solvable and on the roadmap. But the v1 already handles 80% of the small changes you'd make to a website.

---

## Troubleshooting

**Bot doesn't respond to messages**
- Verify the webhook is set: `curl https://api.telegram.org/botYOUR_TOKEN/getWebhookInfo`
- Check `url` is your Worker URL and `last_error_message` is empty
- Make sure your Telegram user ID matches `ALLOWED_TELEGRAM_USER_ID`

**"Failed to trigger GitHub Actions"**
- Check your `GITHUB_PAT` has `repo` and `workflow` scopes
- Verify the repo name in the `projects` array matches exactly (case-sensitive, `username/repo` format)
- Make sure `.github/workflows/telegram-devops.yml` exists in the target repo

**Claude Code doesn't make the right changes**
- Be specific: "Change the hero section background color to #1a1a2e in portfolio" beats "make it darker"
- Mention the component or section name if you know it
- For complex changes, break them into smaller instructions

**Tests fail after changes**
- Claude auto-fixes once. If it still fails, check the GitHub Actions logs
- Some test frameworks need specific config — make sure `npm test -- --watchAll=false --ci` works locally

**Deploy doesn't happen**
- Check that `VERCEL_TOKEN`, `VERCEL_ORG_ID`, and `VERCEL_PROJECT_ID` are set correctly
- Run `vercel link` locally in your project to generate the IDs

---

## Project structure

```
shipit/
├── cloudflare-worker/
│   ├── src/
│   │   └── index.js          # The Worker — auth, routing, dispatch
│   ├── package.json           # Worker dependencies
│   └── wrangler.toml          # Cloudflare config
├── .github/
│   └── workflows/
│       └── telegram-devops.yml  # The pipeline — Claude Code, test, push, deploy
├── scripts/
│   └── setup.sh               # Guided setup script
├── architecture.mermaid        # Architecture diagram (Mermaid)
├── LICENSE                     # MIT
└── README.md                   # You are here
```

The Worker is ~190 lines of JavaScript. The workflow is ~330 lines of YAML. That's the entire product.

---

## Extending it

**Add a new project:** Update the `PROJECTS` secret with the new entry, and copy the workflow into the new repo.

**Change the AI model:** Edit the `claude -p` call in the workflow. You can adjust the prompt, add constraints, or change the allowed tools.

**Add a deploy target:** The workflow has commented-out sections for Netlify and GitHub Pages. Uncomment and configure.

**Custom notifications:** All Telegram messages are sent with `sendTelegram()` in the Worker and `curl` in the workflow. Modify the text, add emojis, or include deploy URLs.

---

## FAQ

**Is this secure?**
The Worker only responds to your Telegram user ID. The GitHub PAT has scoped permissions. Claude Code runs in an ephemeral GitHub Actions container that's destroyed after each run. No credentials are stored at rest.

**What repos does it work with?**
Any repo that can `npm ci && npm test && npm run build`. It's tested with React, Next.js, and Vite projects. It should work with any Node.js project.

**Can I use it with TypeScript projects?**
Yes. Claude Code understands TypeScript and will maintain your types.

**How much does Claude API cost?**
Simple changes (text edits, adding items) cost ~$0.01–0.03. Complex changes (new components, multi-file edits) cost ~$0.05–0.10. At 30 deploys/month, expect $1–3.

**Can multiple people use the same bot?**
Not in v1. The `ALLOWED_TELEGRAM_USER_ID` is a single user check. Multi-user support is on the roadmap.

---

## Contributing

This is an early-stage project. If you find it useful, the best thing you can do is:

1. Try it on one of your projects and tell me what broke
2. Open an issue with your use case
3. Star the repo if you want to follow along

Pull requests welcome for bug fixes, new deploy targets, and documentation improvements.

---

## License

MIT — use it however you want.

---

**Built by [Krishna](https://github.com/chaitanyamean)** — Principal Engineer exploring what happens when you put AI agents between a chat message and a production deployment.
