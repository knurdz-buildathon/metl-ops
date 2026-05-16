#!/bin/bash
# Metl SonarQube Initialization Script
# Waits for SonarQube to be healthy, sets admin password, creates default project.

set -e

SONARQUBE_URL="${SONARQUBE_URL:-http://sonarqube:9000}"
SONARQUBE_ADMIN_PASSWORD="${SONARQUBE_ADMIN_PASSWORD:-changeme}"
OLD_PASSWORD="admin"
MAX_RETRIES=60
SLEEP=10

echo "=== SonarQube Init ==="
echo "URL: $SONARQUBE_URL"

# Wait for SonarQube to be up
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "$SONARQUBE_URL/api/system/status" > /dev/null 2>&1; then
        echo "SonarQube is up after $((i * SLEEP))s"
        break
    fi
    echo "Waiting for SonarQube ($i/$MAX_RETRIES)..."
    sleep $SLEEP
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "ERROR: SonarQube did not become ready"
        exit 1
    fi
done

echo "Changing default admin password..."
curl -sf -u "admin:$OLD_PASSWORD" \
    -X POST \
    "${SONARQUBE_URL}/api/users/change_password?login=admin&previousPassword=${OLD_PASSWORD}&password=${SONARQUBE_ADMIN_PASSWORD}" \
    || echo "Password may already be changed"

echo "Creating default 'metl' quality gate..."
# Create a basic quality gate for Python / TS projects
curl -sf -u "admin:${SONARQUBE_ADMIN_PASSWORD}" \
    -X POST \
    "${SONARQUBE_URL}/api/qualitygates/create?name=metl-default" \
    || echo "Quality gate may already exist"

echo "SonarQube initialization complete."
