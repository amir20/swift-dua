#!/usr/bin/env node
/**
 * Generates the changelog data the site renders, straight from git history.
 *
 * Why a build step: the changelog should never drift from what actually
 * shipped, so we derive it from the release tags (`v*`) rather than hand-curate
 * a list. `pnpm run build` (and `dev`) run this first via the package scripts,
 * and CI checks out full history (fetch-depth: 0) so the deployed site reflects
 * every release. The output, src/lib/changelog.json, is committed so that
 * `svelte-check` and a fresh `vite dev` work without a generate step — the
 * build just refreshes it.
 *
 * How it reads history: Halo's git log has two eras. Early releases were merged
 * with descriptive, type-prefixed PR branch names (feat/reclaim-to-trash); later
 * work lands as conventional commits (feat:, fix:). We walk each release range
 * on the first-parent line — the canonical "what landed on main" — and turn each
 * commit into a changelog entry: merge commits resolve to their best inner
 * commit (so a weak branch name like claude/… still surfaces the real "Add …"
 * subject), direct commits parse their conventional prefix. Noise (ci, chore,
 * deps, docs, style, website-only changes, and trivial subjects) is dropped.
 *
 * The script is defensive: if git is unavailable or no tags are found (e.g. a
 * shallow clone), it leaves any existing changelog.json untouched instead of
 * clobbering it with an empty list.
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = resolve(HERE, '..', 'src', 'lib', 'changelog.json');

/** Run git from the repo (cwd is docs/, git walks up to find .git). */
function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).trim();
}

// ---- classification -------------------------------------------------------

// Conventional-commit / branch-prefix types we surface, mapped to a section.
const KIND_FOR_TYPE = {
  feat: 'added',
  feature: 'added',
  fix: 'fixed',
  bugfix: 'fixed',
  hotfix: 'fixed',
  perf: 'improved',
  improve: 'improved',
  improvement: 'improved'
};

// Types that are real but never user-facing — dropped from a public changelog.
const NOISE_TYPES = new Set([
  'ci',
  'chore',
  'build',
  'test',
  'tests',
  'docs',
  'doc',
  'style',
  'refactor',
  'deps',
  'dep',
  'renovate',
  'release',
  'cleanup',
  'clean',
  'wip',
  'revert'
]);

// Subjects that carry no user-facing meaning, regardless of type.
const TRIVIAL = [
  /^init$/i,
  /^progress$/i,
  /^wip\b/i,
  /^fixup\b/i,
  /^clean\s*up$/i,
  /^updates?\b/i,
  /^adds? (release.?it|website|files|modules|tests?)\b/i,
  /^improves? docs$/i,
  /^merge branch\b/i,
  /^merge remote/i,
  /^address (pr )?review/i,
  /^bump version/i,
  /^format(ting)?$/i,
  /^lint$/i,
  /^typo/i
];

/** Pull a `type` / `scope` / `desc` out of a conventional-commit subject. */
function parseConventional(subject) {
  const m = subject.match(/^(\w+)(?:\(([^)]*)\))?!?:\s*(.+)$/);
  if (!m) return null;
  return { type: m[1].toLowerCase(), scope: (m[2] || '').toLowerCase(), desc: m[3].trim() };
}

/** Humanize a branch tail (foo-bar/baz -> "Foo bar baz") or sentence-case text. */
function humanize(text) {
  const s = text
    .replace(/[-_/]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!s) return s;
  return s[0].toUpperCase() + s.slice(1);
}

/** Tidy a commit description: collapse whitespace, sentence-case, no trailing dot. */
function cleanDesc(desc) {
  const s = desc.replace(/\s+/g, ' ').trim().replace(/\.$/, '');
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

function isTrivial(subject) {
  return TRIVIAL.some((re) => re.test(subject));
}

/**
 * Rank an inner (merged-in) commit subject as a candidate to represent its PR.
 * Higher is better; negatives are excluded. Lets a merge with a vague branch
 * name still surface the meaningful "feat:/Add …" commit inside it.
 */
function scoreInner(subject) {
  if (isTrivial(subject)) return -100;
  const conv = parseConventional(subject);
  if (conv) {
    if (NOISE_TYPES.has(conv.type)) return -100;
    if (conv.type in KIND_FOR_TYPE) return conv.type.startsWith('feat') ? 100 : 90;
    return 10;
  }
  if (/^add(s|ed)?\b/i.test(subject)) return 60;
  if (/^(fix|fixes|fixed)\b/i.test(subject)) return 55;
  if (/^(report|support|improve|enable|introduce|bring|make)\b/i.test(subject)) return 45;
  return 20;
}

/** Map a parsed commit/branch to {kind, text} or null to drop it. */
function toEntry({ type, desc }) {
  if (type && NOISE_TYPES.has(type)) return null;
  if (isTrivial(desc)) return null;

  let kind = type ? KIND_FOR_TYPE[type] : undefined;
  if (!kind) {
    // No (or unknown) type prefix — infer from the wording.
    if (/^add(s|ed)?\b/i.test(desc)) kind = 'added';
    else if (/^(fix|fixes|fixed|prevent|stop|guard|resolve)\b/i.test(desc)) kind = 'fixed';
    else if (/^report\b/i.test(desc)) kind = 'fixed';
    else kind = 'improved';
  }

  // Drop the leading verb so each entry reads as a noun phrase under its
  // section heading ("Added: On-device folder overview", not "Add …").
  let text = cleanDesc(desc);
  if (kind === 'added') text = text.replace(/^add(s|ed)?\s+/i, '');
  else if (kind === 'fixed') text = text.replace(/^fix(es|ed)?\s+/i, '');
  text = text ? text[0].toUpperCase() + text.slice(1) : text;
  return { kind, text };
}

// ---- per-commit resolution ------------------------------------------------

const MERGE_RE = /^Merge pull request #(\d+) from [^/]+\/(.+)$/;

/**
 * Turn one first-parent commit into an entry (or null). For merges, prefer the
 * best inner commit; classify by the branch-name prefix when it's meaningful.
 */
function entryForCommit({ subject, parents }) {
  const merge = subject.match(MERGE_RE);
  if (merge) {
    const pr = Number(merge[1]);
    const branch = merge[2];
    const slash = branch.indexOf('/');
    const branchType = slash > 0 ? branch.slice(0, slash).toLowerCase() : '';
    const branchTail = slash > 0 ? branch.slice(slash + 1) : branch;

    // A clearly-noise branch (ci/, chore/, renovate/…) is dropped outright.
    if (NOISE_TYPES.has(branchType)) return null;

    // Find the strongest commit that was merged in.
    let best = null;
    if (parents.length >= 2) {
      const inner = git('log', `${parents[0]}..${parents[1]}`, '--no-merges', '--pretty=format:%s')
        .split('\n')
        .map((s) => s.trim())
        .filter(Boolean);
      for (const s of inner) {
        const score = scoreInner(s);
        if (!best || score > best.score) best = { subject: s, score };
      }
    }

    let entry;
    if (best && best.score > 0) {
      const conv = parseConventional(best.subject);
      entry = toEntry(conv ?? { type: '', desc: best.subject });
    }
    // Fall back to the (type-prefixed) branch name when no inner commit won.
    if (!entry) {
      const type = branchType in KIND_FOR_TYPE ? branchType : '';
      entry = toEntry({ type, desc: humanize(branchTail) });
    }
    if (!entry) return null;
    return { ...entry, pr };
  }

  // Direct-to-main commit.
  const conv = parseConventional(subject);
  if (conv) {
    if (conv.scope === 'site') return null; // website-only churn isn't app news
    return toEntry(conv);
  }
  return toEntry({ type: '', desc: subject });
}

// ---- range walking --------------------------------------------------------

/** First-parent commits in `range`, newest first. */
function commitsIn(range) {
  const out = git('log', range, '--first-parent', '--pretty=format:%H\t%P\t%s');
  if (!out) return [];
  return out
    .split('\n')
    .map((row) => row.trim())
    .filter(Boolean)
    .map((row) => {
      const [hash, parents, subject] = row.split('\t');
      return { hash, parents: parents ? parents.split(' ') : [], subject: subject ?? '' };
    });
}

/** Collapse duplicate entries (same kind + text), keeping the first PR seen. */
function dedupe(entries) {
  const seen = new Map();
  for (const e of entries) {
    const key = `${e.kind}::${e.text.toLowerCase()}`;
    if (!seen.has(key)) seen.set(key, e);
    else if (e.pr && !seen.get(key).pr) seen.get(key).pr = e.pr;
  }
  return [...seen.values()];
}

function build() {
  const tags = git('tag', '-l', 'v*', '--sort=-v:refname').split('\n').filter(Boolean);
  if (tags.length === 0) return null;

  const order = { added: 0, improved: 1, fixed: 2 };
  const releases = [];
  for (let i = 0; i < tags.length; i++) {
    const tag = tags[i];
    const older = tags[i + 1]; // tags are newest-first
    const range = older ? `${older}..${tag}` : tag;
    const date = git('log', '-1', '--format=%as', tag);

    const entries = dedupe(commitsIn(range).map(entryForCommit).filter(Boolean));
    if (entries.length === 0) continue; // skip empty re-tags / churn-only releases

    entries.sort((a, b) => order[a.kind] - order[b.kind]);
    releases.push({ version: tag.replace(/^v/, ''), tag, date, changes: entries });
  }

  // Drop entries that repeat across releases (messy history can land the same
  // feature in two ranges, e.g. Sparkle). Keep the earliest — that's when it
  // first shipped — by sweeping from the oldest release to the newest.
  const seen = new Set();
  for (let i = releases.length - 1; i >= 0; i--) {
    releases[i].changes = releases[i].changes.filter((c) => {
      const key = `${c.kind}::${c.text.toLowerCase()}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }
  return releases.filter((r) => r.changes.length > 0);
}

// ---- main -----------------------------------------------------------------

let releases = null;
try {
  releases = build();
} catch (err) {
  console.warn(`[changelog] git unavailable, keeping existing data: ${err.message}`);
}

if (!releases || releases.length === 0) {
  if (existsSync(OUT)) {
    console.warn('[changelog] no releases derived; leaving existing changelog.json in place');
    process.exit(0);
  }
  releases = [];
}

const prev = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
const next = JSON.stringify(releases, null, 2) + '\n';
if (prev !== next) {
  writeFileSync(OUT, next);
  console.log(`[changelog] wrote ${releases.length} releases to changelog.json`);
} else {
  console.log('[changelog] up to date');
}
