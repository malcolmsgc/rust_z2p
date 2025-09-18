#!/usr/bin/env bash

set -x
set -eo pipefail


# - `command -v sqlx` finds the path to the `sqlx` executable (e.g., `/usr/local/bin/sqlx`).
# - `[ -x ... ]` checks if that path exists and is executable.
# - The `!` negates the test: if `sqlx` is not found or not executable, the block runs.
# - `>&2 echo ...` prints the message to stderr (standard error).
if ! [ -x "$(command -v sqlx)" ]; then
echo >&2 "Error: sqlx is not installed."
echo >&2 "Use:"
echo >&2 "  cargo install --version='~0.8' sqlx-cli \
--no-default-features --feature rustls,postgres"
echo >&2 "to install it."
exit 1
fi


# check if custom parameter has been set, otherwise use default values
DB_PORT="${POSTGRES_PORT:=5432}"
SUPERUSER="${SUPERUSER:=postgres}"
SUPERUSER_PWD="${SUPERUSER_PWD:=postgres}"
APP_USER="${APP_USER:=app}"
APP_USER_PW="${APP_USER_PWD:=secret}"
APP_DB_NAME="${APP_DB_NAME:=newsletter}"


# Skip Docker if dockerised PGSQL DB already running
# - Note you can initialise a DB by setting SKIP_DOCKER to any value 
#   (it is not a boolean evaluation, rather a string length check using -z):
#       SKIP_DOCKER=anystring ./scripts/init_db.sh
if [[ -z "${SKIP_DOCKER}" ]]; then
    # Launch postgres using Docker
    # Note, max connection number increased to 1000 for testing
    CONTAINER_NAME="postgres"
    docker run \
        --env POSTGRES_USER=${SUPERUSER} \
        --env POSTGRES_PASSWORD=${SUPERUSER_PWD} \
        --health-cmd="pg_isready -U ${SUPERUSER} || exit 1" \
        --health-interval=1s \
        --health-timeout=5s \
        --health-retries=5 \
        --publish "${DB_PORT}":5432 \
        --detach \
        --name "${CONTAINER_NAME}" \
        postgres -N 1000


    # Wait for postgres to be ready to accept connections
    # - The `until ...; do ...; done` loop runs until the condition inside the brackets (`[ ... ]`) is true.
    # - `$(...)` is command substitution: it runs the command inside and replaces it with its output.
    # - The `-f` flag in `docker inspect -f` stands for “format”. It allows you to specify a Go template to format the output of `docker inspect`.
    until [ \
        "$(docker inspect -f "{{.State.Health.Status}}" ${CONTAINER_NAME})" == \
        "healthy" \
    ]; do
        >&2 echo "Postgres is still unavailable - sleeping"
        sleep 1
    done

    # Create the application user
    CREATE_QUERY="CREATE USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';"
    docker exec -it "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -c "${CREATE_QUERY}"

    # Grant create DB rights to app user
    GRANT_QUERY="ALTER USER ${APP_USER} CREATEDB;"
    docker exec -it "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -c "${GRANT_QUERY}"
fi

echo "Postgres is up and running on port ${DB_PORT}!"
echo "Running migrations now..."

# Create the application database
DATABASE_URL=postgres://${APP_USER}:${APP_USER_PWD}@localhost:${DB_PORT}/${APP_DB_NAME}
export DATABASE_URL
sqlx database create
sqlx migrate run
echo "Postgres has been migrated, ready to go!"