#!/bin/bash
# git.sh — Git helpers: slugify, branch check, create/rename branch

# --- Helper: slugify a title ---
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | awk '{for(i=1;i<=NF&&i<=5;i++) printf "%s-",$i}' | sed 's/-$//'
}

# --- Check if current branch is already linked ---
check_branch_linked() {
  CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
  if echo "$CURRENT_BRANCH" | grep -qE '^[a-z]+/[A-Z]+-[0-9]+-[a-z0-9-]+$'; then
    ISSUE_ID=$(echo "$CURRENT_BRANCH" | grep -oE '[A-Z]+-[0-9]+')
    echo "Already linked to $ISSUE_ID on branch: $CURRENT_BRANCH"
    exit 0
  fi
}

# --- Create or rename branch ---
create_or_rename_branch() {
  SLUG=$(slugify "$ISSUE_TITLE")
  BRANCH_NAME="$GIT_NAME/$ISSUE_ID-$SLUG"

  echo ""

  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    echo "Creating branch: $BRANCH_NAME"
    git pull origin "$CURRENT_BRANCH" --quiet
    git checkout -b "$BRANCH_NAME"
  else
    echo "Renaming branch '$CURRENT_BRANCH' -> '$BRANCH_NAME'"
    git branch -m "$BRANCH_NAME"
  fi
}

# --- Print summary ---
print_summary() {
  echo ""
  ISSUE_URL=$(linear_query \
    'query ($id: String!) { issue(id: $id) { url } }' \
    "$(jq -n --arg id "$ISSUE_ID" '{id: $id}')" \
    | jq -r '.data.issue.url // empty')

  echo "Linked to $ISSUE_ID: $ISSUE_TITLE"
  echo ""
  echo "   Branch:  $BRANCH_NAME"
  if [ -n "$ISSUE_URL" ]; then
    echo "   Issue:   $ISSUE_URL"
  fi
  echo "   Commits: Prefix with \"$ISSUE_ID: ...\""
}
