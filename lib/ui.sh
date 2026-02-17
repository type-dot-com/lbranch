#!/bin/bash
# ui.sh — Interactive menu: mode selection, issue picking, quick-pick display

# --- Helper: display issues and pick one, with option to create ---
pick_issue() {
  local RESULT="$1"
  local JQ_PATH="$2"  # e.g., ".data.issueSearch.nodes" or ".data.viewer.assignedIssues.nodes"
  local COUNT

  COUNT=$(echo "$RESULT" | jq "$JQ_PATH | length")

  if [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ]; then
    echo "   No issues found."
    echo ""
    echo "   c) Create a new issue"
    echo ""
    echo -n "Pick: "
    read CHOICE
    if [ "$CHOICE" = "c" ] || [ "$CHOICE" = "C" ]; then
      create_issue
    else
      echo "No issue selected"
      exit 1
    fi
    return
  fi

  echo ""
  for i in $(seq 0 $((COUNT - 1))); do
    local ID TITLE STATE
    ID=$(echo "$RESULT" | jq -r "$JQ_PATH[$i].identifier")
    TITLE=$(echo "$RESULT" | jq -r "$JQ_PATH[$i].title")
    STATE=$(echo "$RESULT" | jq -r "$JQ_PATH[$i].state.name // empty")
    if [ -n "$STATE" ]; then
      echo "  $((i+1))) $ID - $TITLE [$STATE]"
    else
      echo "  $((i+1))) $ID - $TITLE"
    fi
  done
  echo ""
  echo "  c) Create a new issue"
  echo ""
  echo -n "Pick (1-$COUNT or c): "
  read CHOICE

  if [ "$CHOICE" = "c" ] || [ "$CHOICE" = "C" ]; then
    create_issue
    return
  fi

  local IDX=$((CHOICE - 1))
  ISSUE_ID=$(echo "$RESULT" | jq -r "$JQ_PATH[$IDX].identifier")
  ISSUE_TITLE=$(echo "$RESULT" | jq -r "$JQ_PATH[$IDX].title")

  if [ -z "$ISSUE_ID" ] || [ "$ISSUE_ID" = "null" ]; then
    echo "Invalid selection"
    exit 1
  fi
}

# --- Main dispatch: resolve an issue from args or interactive menu ---
resolve_issue() {
  local ARG="$*"
  ISSUE_ID=""
  ISSUE_TITLE=""

  # Resolve team key for regex matching
  TEAM_KEY=$(get_team_key)

  # Build issue ID regex dynamically from team key, or use generic pattern
  if [ -n "$TEAM_KEY" ]; then
    ISSUE_RE="^${TEAM_KEY}-[0-9]+$"
  else
    ISSUE_RE='^[A-Z]+-[0-9]+$'
  fi

  if echo "$ARG" | grep -qE "$ISSUE_RE"; then
    # Mode 1: Specific issue ID
    echo "Looking up $ARG..."
    RESULT=$(linear_query \
      'query ($id: String!) { issue(id: $id) { identifier title state { name } } }' \
      "$(jq -n --arg id "$ARG" '{id: $id}')")
    ISSUE_ID=$(echo "$RESULT" | jq -r '.data.issue.identifier // empty')
    ISSUE_TITLE=$(echo "$RESULT" | jq -r '.data.issue.title // empty')

    if [ -z "$ISSUE_ID" ]; then
      echo "Issue $ARG not found in Linear"
      exit 1
    fi
    echo "   Found: $ISSUE_ID - $ISSUE_TITLE"

  elif [ "$CREATE_MODE" = true ]; then
    create_issue "$ARG"

  elif [ -n "$ARG" ]; then
    if [ "$AUTO_MODE" = true ]; then
      # Auto mode: create a new issue with the description as the title
      echo "Creating Linear issue: \"$ARG\"..."
      create_issue "$ARG"
    else
      # Mode 2: Keyword search
      echo "Searching Linear for \"$ARG\"..."
      RESULT=$(linear_query \
        'query ($q: String!) { issueSearch(query: $q, first: 10) { nodes { identifier title state { name } } } }' \
        "$(jq -n --arg q "$ARG" '{q: $q}')")
      pick_issue "$RESULT" ".data.issueSearch.nodes"
    fi

  else
    if [ "$AUTO_MODE" = true ]; then
      echo "--auto requires an issue ID or description"
      echo "   Usage: lbranch --auto ENG-142"
      echo "   Usage: lbranch --auto \"task description\""
      exit 1
    fi

    # Mode 3: Interactive menu
    show_interactive_menu
  fi

  if [ -z "$ISSUE_ID" ]; then
    echo "No issue selected"
    exit 1
  fi
}

# --- Interactive menu with quick-picks ---
show_interactive_menu() {
  echo ""
  echo "  1) Browse my assigned issues"
  echo "  2) Search by keyword"
  echo "  3) Create a new issue"
  echo ""

  # Fetch quick-pick issues: assigned To Do + recently created
  TODO_RESULT=$(linear_query '{ viewer { assignedIssues(first: 3, filter: { state: { type: { eq: "unstarted" } } }, orderBy: updatedAt) { nodes { identifier title state { name } } } } }')
  RECENT_RESULT=$(linear_query '{ issues(first: 6, filter: { assignee: { null: true }, state: { type: { nin: ["completed", "canceled"] } } }, orderBy: createdAt) { nodes { identifier title state { name } } } }')

  TODO_COUNT=$(echo "$TODO_RESULT" | jq '.data.viewer.assignedIssues.nodes | length // 0')
  RECENT_COUNT=$(echo "$RECENT_RESULT" | jq '.data.issues.nodes | length // 0')

  # Collect quick-pick issues (deduplicated)
  QUICK_PICK_IDS=()
  QUICK_PICK_TITLES=()
  QUICK_PICK_STATES=()
  SEEN_IDS=""

  # Add To Do issues
  if [ "$TODO_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  -- My Todos --"
    for i in $(seq 0 $((TODO_COUNT - 1))); do
      QID=$(echo "$TODO_RESULT" | jq -r ".data.viewer.assignedIssues.nodes[$i].identifier")
      QTITLE=$(echo "$TODO_RESULT" | jq -r ".data.viewer.assignedIssues.nodes[$i].title")
      QSTATE=$(echo "$TODO_RESULT" | jq -r ".data.viewer.assignedIssues.nodes[$i].state.name // empty")
      if echo "$SEEN_IDS" | grep -qF "$QID"; then continue; fi
      SEEN_IDS="$SEEN_IDS $QID"
      QUICK_PICK_IDS+=("$QID")
      QUICK_PICK_TITLES+=("$QTITLE")
      QUICK_PICK_STATES+=("$QSTATE")
      NUM=$((${#QUICK_PICK_IDS[@]} + 3))
      echo "  $NUM) $QID - $QTITLE [$QSTATE]"
    done
    echo ""
  fi

  # Add recently created issues (up to 3 after dedup)
  RECENT_ADDED=0
  if [ "$RECENT_COUNT" -gt 0 ] 2>/dev/null; then
    PRINTED_HEADER=false
    for i in $(seq 0 $((RECENT_COUNT - 1))); do
      QID=$(echo "$RECENT_RESULT" | jq -r ".data.issues.nodes[$i].identifier")
      QTITLE=$(echo "$RECENT_RESULT" | jq -r ".data.issues.nodes[$i].title")
      QSTATE=$(echo "$RECENT_RESULT" | jq -r ".data.issues.nodes[$i].state.name // empty")
      if echo "$SEEN_IDS" | grep -qF "$QID"; then continue; fi
      if [ "$RECENT_ADDED" -ge 3 ]; then break; fi
      SEEN_IDS="$SEEN_IDS $QID"
      if [ "$PRINTED_HEADER" = false ]; then
        echo "  -- Recent --"
        PRINTED_HEADER=true
      fi
      QUICK_PICK_IDS+=("$QID")
      QUICK_PICK_TITLES+=("$QTITLE")
      QUICK_PICK_STATES+=("$QSTATE")
      RECENT_ADDED=$((RECENT_ADDED + 1))
      NUM=$((${#QUICK_PICK_IDS[@]} + 3))
      echo "  $NUM) $QID - $QTITLE [$QSTATE]"
    done
    if [ "$PRINTED_HEADER" = true ]; then echo ""; fi
  fi

  TOTAL_QUICK=${#QUICK_PICK_IDS[@]}
  MAX_CHOICE=$((3 + TOTAL_QUICK))

  echo -n "Pick (1-$MAX_CHOICE): "
  read MODE

  case "$MODE" in
    1)
      echo ""
      echo "Your open issues:"
      RESULT=$(linear_query '{ viewer { assignedIssues(first: 10, filter: { state: { type: { nin: ["completed", "canceled"] } } }) { nodes { identifier title state { name } priority } } } }')
      pick_issue "$RESULT" ".data.viewer.assignedIssues.nodes"
      ;;
    2)
      echo -n "  Search: "
      read SEARCH_TERM
      echo "Searching Linear for \"$SEARCH_TERM\"..."
      RESULT=$(linear_query \
        'query ($q: String!) { issueSearch(query: $q, first: 10) { nodes { identifier title state { name } } } }' \
        "$(jq -n --arg q "$SEARCH_TERM" '{q: $q}')")
      pick_issue "$RESULT" ".data.issueSearch.nodes"
      ;;
    3)
      create_issue
      ;;
    *)
      # Check if it's a quick-pick selection
      if [ "$MODE" -gt 3 ] 2>/dev/null && [ "$MODE" -le "$MAX_CHOICE" ] 2>/dev/null; then
        IDX=$((MODE - 4))
        ISSUE_ID="${QUICK_PICK_IDS[$IDX]}"
        ISSUE_TITLE="${QUICK_PICK_TITLES[$IDX]}"
        echo "  Selected: $ISSUE_ID - $ISSUE_TITLE"
      else
        echo "Invalid choice"
        exit 1
      fi
      ;;
  esac
}
