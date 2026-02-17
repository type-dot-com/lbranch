#!/bin/bash
# linear.sh — Linear GraphQL API helpers

# --- Helper: call Linear GraphQL ---
linear_query() {
  local QUERY="$1"
  local VARIABLES="${2:-}"
  local PAYLOAD

  if [ -n "$VARIABLES" ]; then
    PAYLOAD=$(jq -n --arg q "$QUERY" --argjson v "$VARIABLES" '{query: $q, variables: $v}')
  else
    PAYLOAD=$(jq -n --arg q "$QUERY" '{query: $q}')
  fi

  curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d "$PAYLOAD"
}

# --- Team config ---
get_team_key() {
  if [ -f "$CONFIG_FILE" ]; then
    jq -r '.teamKey // empty' "$CONFIG_FILE" 2>/dev/null
  fi
}

get_team_id() {
  # Return cached team ID if available
  if [ -f "$CONFIG_FILE" ]; then
    local CACHED_ID
    CACHED_ID=$(jq -r '.teamId // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$CACHED_ID" ]; then
      echo "$CACHED_ID"
      return
    fi
  fi

  local RESULT
  RESULT=$(linear_query '{ teams { nodes { id name key } } }')
  local TEAM_COUNT
  TEAM_COUNT=$(echo "$RESULT" | jq '.data.teams.nodes | length')

  local TEAM_ID TEAM_KEY
  if [ "$TEAM_COUNT" = "1" ] || [ "$AUTO_MODE" = true ]; then
    TEAM_ID=$(echo "$RESULT" | jq -r '.data.teams.nodes[0].id')
    TEAM_KEY=$(echo "$RESULT" | jq -r '.data.teams.nodes[0].key')
  else
    echo "" >&2
    echo "  Which team?" >&2
    for i in $(seq 0 $((TEAM_COUNT - 1))); do
      local NAME KEY
      NAME=$(echo "$RESULT" | jq -r ".data.teams.nodes[$i].name")
      KEY=$(echo "$RESULT" | jq -r ".data.teams.nodes[$i].key")
      echo "  $((i+1))) $NAME ($KEY)" >&2
    done
    echo -n "  Pick (1-$TEAM_COUNT): " >&2
    read TEAM_CHOICE
    TEAM_ID=$(echo "$RESULT" | jq -r ".data.teams.nodes[$((TEAM_CHOICE - 1))].id")
    TEAM_KEY=$(echo "$RESULT" | jq -r ".data.teams.nodes[$((TEAM_CHOICE - 1))].key")
  fi

  # Save for next time
  mkdir -p "$CONFIG_DIR"
  jq -n --arg id "$TEAM_ID" --arg key "$TEAM_KEY" '{teamId: $id, teamKey: $key}' > "$CONFIG_FILE"
  echo "  Saved team selection ($TEAM_KEY) to $CONFIG_FILE" >&2
  echo "$TEAM_ID"
}

# --- Helper: create a new Linear issue ---
# Usage: create_issue ["optional title for auto mode"]
create_issue() {
  local NEW_TITLE="${1:-}"

  if [ -z "$NEW_TITLE" ]; then
    echo ""
    echo -n "  Issue title: "
    read NEW_TITLE
  fi

  if [ -z "$NEW_TITLE" ]; then
    echo "Title is required"
    exit 1
  fi

  local TEAM_ID
  TEAM_ID=$(get_team_id)

  echo "  Creating issue..."
  local RESULT
  RESULT=$(linear_query \
    'mutation ($title: String!, $teamId: String!) { issueCreate(input: { title: $title, teamId: $teamId }) { success issue { identifier title } } }' \
    "$(jq -n --arg t "$NEW_TITLE" --arg tid "$TEAM_ID" '{title: $t, teamId: $tid}')")

  ISSUE_ID=$(echo "$RESULT" | jq -r '.data.issueCreate.issue.identifier // empty')
  ISSUE_TITLE=$(echo "$RESULT" | jq -r '.data.issueCreate.issue.title // empty')

  if [ -z "$ISSUE_ID" ]; then
    echo "Failed to create issue"
    echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    exit 1
  fi

  echo "  Created $ISSUE_ID: $ISSUE_TITLE"
}

# --- Assign to me and mark In Progress ---
update_linear_issue() {
  echo "Updating issue in Linear..."

  # Get my user ID and the "In Progress" state ID
  VIEWER_ID=$(linear_query '{ viewer { id } }' | jq -r '.data.viewer.id // empty')

  IN_PROGRESS_ID=$(linear_query \
    'query ($id: String!) { issue(id: $id) { team { states { nodes { id name type } } } } }' \
    "$(jq -n --arg id "$ISSUE_ID" '{id: $id}')" \
    | jq -r '.data.issue.team.states.nodes[] | select(.name == "In Progress" or (.type == "started" and (.name | test("progress";"i")))) | .id' | head -1)

  # Build update payload
  UPDATE_VARS=$(jq -n --arg id "$ISSUE_ID" '{id: $id}')
  if [ -n "$VIEWER_ID" ]; then
    UPDATE_VARS=$(echo "$UPDATE_VARS" | jq --arg uid "$VIEWER_ID" '. + {assigneeId: $uid}')
  fi
  if [ -n "$IN_PROGRESS_ID" ]; then
    UPDATE_VARS=$(echo "$UPDATE_VARS" | jq --arg sid "$IN_PROGRESS_ID" '. + {stateId: $sid}')
  fi

  linear_query \
    'mutation ($id: String!, $assigneeId: String, $stateId: String) { issueUpdate(id: $id, input: { assigneeId: $assigneeId, stateId: $stateId }) { success } }' \
    "$UPDATE_VARS" > /dev/null
}
