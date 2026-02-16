/**
 * ShipIt — Cloudflare Worker
 * Telegram → GitHub Actions bridge
 *
 * This is the only always-on piece. It:
 * 1. Receives Telegram webhook messages
 * 2. Validates the sender
 * 3. Detects which project you're referring to
 * 4. Triggers GitHub Actions via repository_dispatch
 * 5. Sends acknowledgment back to Telegram
 *
 * Zero code editing needed. Projects are configured via the PROJECTS secret.
 * Format: name:owner/repo:keyword1,keyword2|name2:owner/repo2:kw1,kw2
 * Set via: npx wrangler secret put PROJECTS
 *
 * Deploy: npx wrangler deploy
 */

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('ShipIt is running! Send me a Telegram message.', {
        status: 200,
      });
    }

    try {
      const update = await request.json();

      if (!update.message || !update.message.text) {
        return new Response('OK', { status: 200 });
      }

      const chatId = update.message.chat.id;
      const userId = update.message.from.id.toString();
      const messageText = update.message.text.trim();

      // ─── Auth ───────────────────────────────────────────
      if (userId !== env.ALLOWED_TELEGRAM_USER_ID) {
        await sendTelegram(env, chatId, '🔒 Unauthorized. This bot is private.');
        return new Response('OK', { status: 200 });
      }

      // ─── Load projects from secret ──────────────────────
      const projects = parseProjects(env.PROJECTS);

      if (projects.length === 0) {
        await sendTelegram(
          env,
          chatId,
          '⚠️ *No projects configured.*\n\n' +
            'Run `./scripts/setup.sh` or set the PROJECTS secret:\n' +
            '`npx wrangler secret put PROJECTS`\n\n' +
            'Format: `name:owner/repo:keyword1,keyword2`'
        );
        return new Response('OK', { status: 200 });
      }

      // ─── Commands ───────────────────────────────────────
      if (messageText === '/start' || messageText === '/help') {
        const example = projects[0].name;
        await sendTelegram(
          env,
          chatId,
          `🚀 *ShipIt — Deploy from Telegram*\n\n` +
            `Just type what you want to change!\n\n` +
            `*Examples:*\n` +
            `• Add Docker to skills section in ${example}\n` +
            `• Change the hero background to dark blue\n` +
            `• Fix typo in about section\n` +
            `• Add a tooltip to the email link\n\n` +
            `*Commands:*\n` +
            `/start — Show this help\n` +
            `/ping — Check if bot is alive\n` +
            `/projects — List connected projects`
        );
        return new Response('OK', { status: 200 });
      }

      if (messageText === '/ping') {
        await sendTelegram(env, chatId, '🏓 Pong! ShipIt is alive and ready.');
        return new Response('OK', { status: 200 });
      }

      if (messageText === '/projects') {
        const list = projects
          .map((p) => `• *${p.name}* → \`${p.repo}\`\n  Keywords: ${p.keywords.join(', ')}`)
          .join('\n\n');
        await sendTelegram(
          env,
          chatId,
          `📂 *Connected Projects:*\n\n${list}\n\n_Default: ${projects[projects.length - 1].name}_`
        );
        return new Response('OK', { status: 200 });
      }

      // ─── Detect project from message ────────────────────
      const project = detectProject(messageText, projects);

      // ─── Acknowledge ────────────────────────────────────
      await sendTelegram(
        env,
        chatId,
        `🚀 *Pipeline Triggered!*\n\n` +
          `*Project:* ${project.name}\n` +
          `*Repo:* \`${project.repo}\`\n` +
          `*Change:* ${messageText}\n\n` +
          `⏳ GitHub Actions is spinning up...`
      );

      // ─── Trigger GitHub Actions ─────────────────────────
      const resp = await fetch(
        `https://api.github.com/repos/${project.repo}/dispatches`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${env.GITHUB_PAT}`,
            Accept: 'application/vnd.github.v3+json',
            'User-Agent': 'ShipIt-Bot',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            event_type: 'telegram-devops',
            client_payload: {
              instruction: messageText,
              chat_id: chatId.toString(),
              project: project.name,
              triggered_by: update.message.from.first_name || 'User',
            },
          }),
        }
      );

      if (!resp.ok) {
        const errorText = await resp.text();
        await sendTelegram(
          env,
          chatId,
          `❌ *Failed to trigger pipeline*\n\n` +
            `Status: ${resp.status}\n` +
            `Error: ${errorText.substring(0, 200)}\n\n` +
            `Check that GITHUB\\_PAT is valid and the repo exists.`
        );
      }

      return new Response('OK', { status: 200 });
    } catch (err) {
      console.error('Worker error:', err);
      return new Response('Internal Error', { status: 500 });
    }
  },
};

// ═══════════════════════════════════════════════════════════
// PROJECT PARSING
// ═══════════════════════════════════════════════════════════
//
// PROJECTS secret format (set once, never edit code):
//
//   portfolio:krishna/my-site:portfolio,my site|hireai:krishna/hireai:hireai,hiring
//
//   Each project:  name:owner/repo:keyword1,keyword2
//   Multiple projects separated by |
//

function parseProjects(raw) {
  if (!raw) return [];
  try {
    return raw
      .split('|')
      .filter((e) => e.trim())
      .map((entry) => {
        const [name, repo, keywordsStr] = entry.split(':').map((s) => s.trim());
        return {
          name,
          repo,
          keywords: keywordsStr
            ? keywordsStr.split(',').map((k) => k.trim().toLowerCase())
            : [name.toLowerCase()],
        };
      });
  } catch (err) {
    console.error('Failed to parse PROJECTS:', err);
    return [];
  }
}

function detectProject(message, projects) {
  const lower = message.toLowerCase();
  for (const project of projects) {
    if (project.keywords.some((kw) => lower.includes(kw))) {
      return project;
    }
  }
  return projects[projects.length - 1];
}

// ═══════════════════════════════════════════════════════════
// TELEGRAM HELPER
// ═══════════════════════════════════════════════════════════

async function sendTelegram(env, chatId, text) {
  try {
    await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text: text,
          parse_mode: 'Markdown',
        }),
      }
    );
  } catch (err) {
    console.error('Telegram send failed:', err);
  }
}
