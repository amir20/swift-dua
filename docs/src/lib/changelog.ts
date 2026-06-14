/**
 * Typed access to the changelog data. The JSON is generated from git tags at
 * build time by scripts/gen-changelog.mjs (run before `dev`/`build`) — never
 * edit changelog.json by hand. Releases are ordered newest-first.
 */
import data from './changelog.json';

export type ChangeKind = 'added' | 'improved' | 'fixed';

export interface Change {
  kind: ChangeKind;
  text: string;
  /** GitHub PR number, when the change came in through one. */
  pr?: number;
}

export interface Release {
  /** e.g. "0.1.5" */
  version: string;
  /** e.g. "v0.1.5" */
  tag: string;
  /** ISO date (YYYY-MM-DD) the release was tagged. */
  date: string;
  changes: Change[];
}

export const releases: Release[] = data as Release[];

export const REPO = 'https://github.com/amir20/Halo.app';
