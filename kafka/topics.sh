#!/bin/sh
# Crea los topics de la biblioteca. Se puede ejecutar varias veces.
set -eu

# Evita que Git Bash transforme las rutas /opt/... de los contenedores.
export MSYS_NO_PATHCONV=1

SERVICIO="${SERVICIO:-broker-1}"
BOOTSTRAP="${BOOTSTRAP:-broker-1:19092}"
SIETE_DIAS=604800000
UN_DIA=86400000

crear() {
  topic=$1
  retencion=$2
  docker compose exec -T "$SERVICIO" /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor 3 \
    --config min.insync.replicas=2 \
    --config cleanup.policy=delete \
    --config retention.ms="$retencion"
}

crear biblioteca.prestamos "$SIETE_DIAS"
crear biblioteca.lecturas "$UN_DIA"
crear biblioteca.prestamos.dlt "$SIETE_DIAS"
crear biblioteca.lecturas.dlt "$SIETE_DIAS"

docker compose exec -T "$SERVICIO" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$BOOTSTRAP" --describe --topics-with-overrides --exclude-internal