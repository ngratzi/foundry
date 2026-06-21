#!/usr/bin/env bash
# Regenerates deploy/<service>/changelog-configmap.yaml from services/<service>/db/changelog/
set -euo pipefail

SERVICE=$1
CHANGELOG_DIR="services/${SERVICE}/db/changelog"
CONFIGMAP_FILE="deploy/${SERVICE}/changelog-configmap.yaml"
PG_HOST="postgres-postgresql.foundry.svc.cluster.local"
PG_DB="foundry"
SCHEMA="${SERVICE//-/_}"

# Collect SQL files in order
SQL_FILES=$(find "${CHANGELOG_DIR}/changes" -name "*.sql" | sort)

# Build master XML includes
INCLUDES=""
for f in $SQL_FILES; do
  filename=$(basename "$f")
  INCLUDES="${INCLUDES}      <include file=\"/changelog/changes/${filename}\"/>\n"
done

# Build ConfigMap data entries for each SQL file
SQL_DATA=""
for f in $SQL_FILES; do
  filename=$(basename "$f")
  content=$(sed 's/^/    /' "$f")
  SQL_DATA="${SQL_DATA}  ${filename}: |\n${content}\n"
done

cat > "${CONFIGMAP_FILE}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${SERVICE}-changelog
  namespace: foundry
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
data:
  db.changelog-master.xml: |
    <?xml version="1.0" encoding="UTF-8"?>
    <databaseChangeLog
      xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.20.xsd">
$(echo -e "$INCLUDES")    </databaseChangeLog>
$(echo -e "$SQL_DATA")EOF

echo "Generated ${CONFIGMAP_FILE}"
