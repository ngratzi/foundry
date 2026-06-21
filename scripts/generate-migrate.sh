#!/usr/bin/env bash
# Regenerates deploy/<service>/migrate.yaml ConfigMap from services/<service>/db/changelog/
set -euo pipefail

SERVICE=$1
CHANGELOG_DIR="services/${SERVICE}/db/changelog"
MIGRATE_FILE="deploy/${SERVICE}/migrate.yaml"
DB_PASSWORD_KEY="password"
PG_HOST="postgres-postgresql.foundry.svc.cluster.local"
PG_DB="foundry"

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

cat > "${MIGRATE_FILE}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${SERVICE}-changelog
  namespace: foundry
data:
  db.changelog-master.xml: |
    <?xml version="1.0" encoding="UTF-8"?>
    <databaseChangeLog
      xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.20.xsd">
$(echo -e "$INCLUDES")    </databaseChangeLog>
$(echo -e "$SQL_DATA")---
apiVersion: batch/v1
kind: Job
metadata:
  name: ${SERVICE}-migrate
  namespace: foundry
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: liquibase
          image: liquibase/liquibase:4.27
          args:
            - --url=jdbc:postgresql://${PG_HOST}:5432/${PG_DB}?currentSchema=${SERVICE//-/_}
            - --username=foundry
            - --password=\$(DB_PASSWORD)
            - --changeLogFile=/changelog/db.changelog-master.xml
            - update
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: ${DB_PASSWORD_KEY}
          volumeMounts:
            - name: changelog
              mountPath: /changelog/changes
            - name: changelog
              mountPath: /changelog/db.changelog-master.xml
              subPath: db.changelog-master.xml
      volumes:
        - name: changelog
          configMap:
            name: ${SERVICE}-changelog
EOF

echo "Generated ${MIGRATE_FILE}"
