#!/usr/bin/env bash
# levantar.sh - levanta Kafka, RabbitMQ, Postgres y los servicios de la biblioteca.
# Uso en Git Bash: bash levantar.sh
set -euo pipefail
cd "$(dirname "$0")"
RAIZ="$(cd .. && pwd)"

# 1. Crear los .env faltantes desde sus ejemplos y detectar valores vacíos.
REPOS="biblioteca-plataforma biblioteca-gateway biblioteca-bff biblioteca-prestamos biblioteca-eventos biblioteca-admin"
for repo in $REPOS; do
  if [ ! -f "$RAIZ/$repo/.env" ]; then
    cp "$RAIZ/$repo/.env.example" "$RAIZ/$repo/.env"
    echo "creado $repo/.env desde .env.example"
  fi
done

faltan=0
for repo in $REPOS; do
  for nombre in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=[[:space:]]*$' "$RAIZ/$repo/.env" | cut -d= -f1); do
    echo "FALTA  $repo/.env: $nombre"
    faltan=1
  done
done
if [ "$faltan" -eq 1 ]; then
  echo "Rellena esos valores y vuelve a correr: bash levantar.sh"
  exit 1
fi

# 2. Los topics deben existir antes de arrancar el consumidor de eventos.
docker compose up -d --wait broker-1 broker-2 broker-3
sh kafka/topics.sh > /dev/null
echo "topics listos: biblioteca.prestamos, biblioteca.lecturas y sus .dlt"

# 3. Construir y arrancar todos los servicios.
docker compose up -d --build --wait

# 4. Comprobar las respuestas HTTP. Un 401 indica que un servicio protegido está vivo.
fallas=0
comprobar() {
  esperado=$1
  url=$2
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
  if [ "$codigo" = "$esperado" ]; then
    echo "OK     $codigo $url"
  else
    echo "FALLA  $codigo (se esperaba $esperado) $url"
    fallas=1
  fi
}
comprobar 200 http://localhost:4200/
comprobar 401 http://localhost:8080/v1/libros
comprobar 401 http://localhost:3000/panel
comprobar 200 http://localhost:3001/libros
comprobar 200 http://localhost:3002/prestamos
comprobar 200 http://localhost:3010/salud
comprobar 401 http://localhost:3020/v1/admin/colas
comprobar 200 http://localhost:8085/actuator/health

docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo "Kafka UI: http://localhost:8085 (tiene que mostrar 3 brokers)"
echo "Para publicar la noche de la biblioteca: cd ../biblioteca-simulador && npm ci && node reproducir.mjs --velocidad 60"
echo "Para bajarlo todo sin borrar datos: docker compose down"
if [ "$fallas" -eq 1 ]; then
  echo "Algun servicio no responde: docker compose logs <servicio> --tail 30"
  exit 1
fi