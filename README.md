# lbranch

Link your git branches to Linear issues. Picks an issue, names your branch, assigns it to you, and marks it In Progress — all in one command.

## Install

### Homebrew

```bash
brew tap fletchrichman/lbranch
brew install lbranch
```

### Manual

```bash
git clone https://github.com/fletchrichman/lbranch.git
cp -r lbranch/bin/lbranch /usr/local/bin/
cp -r lbranch/lib/ /usr/local/lib/lbranch/
```

## Setup

Set your Linear API key:

```bash
export LINEAR_API_KEY=lin_api_xxxxx
```

Generate one at **Linear > Settings > API > Personal API Keys**.

You can also add `LINEAR_API_KEY=lin_api_xxxxx` to a `.env` file in any git repo root as a fallback.

## Usage

```bash
lbranch                  # Interactive: browse, search, or create issues
lbranch ENG-142          # Link to a specific issue
lbranch "search terms"   # Search issues by keyword
lbranch -c               # Jump straight to creating a new issue
lbranch -c "Fix login"   # Create issue with title and branch in one shot
```

### Non-interactive (CI)

```bash
lbranch --auto "task description"   # Creates issue + branch
lbranch --auto ENG-142              # Links to existing issue
```

## What it does

1. Finds or creates a Linear issue
2. Assigns the issue to you and sets it to **In Progress**
3. Creates (or renames) your branch: `yourname/ENG-142-short-slug`

## Branch format

```
<username>/<TEAM-123>-<slug>
```

The username comes from `git config user.name`. The team prefix (e.g., `ENG`, `DEV`) is fetched from Linear and cached.

## Configuration

Config is stored at `~/.config/lbranch/config` and caches your selected team's ID and issue key prefix. Delete this file to re-select your team.

## Dependencies

- `jq` — install with `brew install jq` or `apt install jq`
- `curl`
- `git`

## License

MIT
