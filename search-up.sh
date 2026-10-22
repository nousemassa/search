#!/usr/bin/env bash
# Проект `search`: свой инстанс SearXNG и своя MCP-обёртка. Своя папка, свой композ, свой лончер.
#
#   bash search-up.sh            # поднять оба сервиса
#   bash search-up.sh status     # проверить JSON-поиск и инструменты MCP
#   bash search-up.sh stop       # остановить
#
# **❗ Про секрет, который нельзя потерять молча.** `SEARXNG_SECRET` перекрывает `server.secret_key` из
# `searxng/settings.yml`. Значение живёт в окружении ПРОЕКТА (`./.env`): `compose` читает `.env` из папки
# СВОЕГО файла, поэтому без значения секрет МОЛЧА откатился бы к умолчанию — настройка безопасности
# изменилась бы без единой строки в журнале. Отсюда два правила:
#   1) источник секрета — ОДИН, и он лежит с проектом (`./.env`, в git не попадает);
#   2) если значения нет ни в окружении, ни в файле — проект ОТКАЗЫВАЕТСЯ стартовать (см. проверку ниже):
#      «проверить нечем» и «всё хорошо» — разные вещи.
# Лончер печатает, какой файл окружения взял: «взял не тот» должно быть видно сразу.
set -euo pipefail

#: Каталог ПРОЕКТА (не воркспейса).
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$PROJECT_DIR/.." && pwd)"
COMPOSE="$PROJECT_DIR/compose.search.yaml"

if [[ -n "${SEARCH_ENV:-}" ]]; then
  ENV_FILE="$SEARCH_ENV"
elif [[ -f "$PROJECT_DIR/.env" ]]; then
  ENV_FILE="$PROJECT_DIR/.env"
elif [[ -f "$WORKSPACE/.env" ]]; then
  ENV_FILE="$WORKSPACE/.env"
  echo "[search] ВНИМАНИЕ: окружения проекта нет — беру корневой $ENV_FILE (проверяю, есть ли там секрет)"
else
  echo "[search] ОСТАНОВ: не нашёл ни ./.env проекта, ни $WORKSPACE/.env" >&2
  exit 2
fi
[[ -f "$ENV_FILE" ]] || { echo "[search] ОСТАНОВ: $ENV_FILE не существует" >&2; exit 2; }
echo "[search] окружение: $ENV_FILE"

#: Без секрета не стартуем: иначе `compose` молча подставит умолчание, и это будет изменение безопасности.
if [[ -z "${SEARXNG_SECRET:-}" ]] && ! grep -qE '^SEARXNG_SECRET=.+' "$ENV_FILE"; then
  echo "[search] ОСТАНОВ: в $ENV_FILE нет непустого SEARXNG_SECRET — иначе секрет поиска стал бы" >&2
  echo "          умолчанием композа, и это изменение НАСТРОЙКИ БЕЗОПАСНОСТИ молча." >&2
  echo "          Возьмите образец: cp .env.example .env и заполните значение." >&2
  exit 2
fi

#: Два файла: общая основа (если проект стоит внутри воркспейса) + окружение проекта.
#: Основа первой, проект второй — он перекрывает; отсутствие любого — не ошибка.
BASE_ENV="${SEARCH_BASE_ENV:-$WORKSPACE/.env}"
ENV_ARGS=()
[[ -f "$BASE_ENV" ]] && ENV_ARGS+=(--env-file "$BASE_ENV")
ENV_ARGS+=(--env-file "$ENV_FILE")
compose() { docker compose "${ENV_ARGS[@]}" -f "$COMPOSE" "$@"; }

#: Сервисы и их хостовые адреса (для `status`). Публикуются только на loopback — см. композ.
declare -A HOST_PORTS=([searxng]=8090 [mcp-searxng]=3001)
ACTION="${1:-up}"

status() {
  local ok=0
  # 1) JSON-поиск: проверяем именно то, чем пользуется наш путь, а не «порт открыт».
  if curl -fsS -m 20 "http://127.0.0.1:${HOST_PORTS[searxng]}/search?q=health&format=json" >/dev/null 2>&1; then
    echo "[search] searxng: JSON-поиск отвечает на 127.0.0.1:${HOST_PORTS[searxng]} ✓"
  else
    echo "[search] searxng: JSON-поиск НЕ отвечает на 127.0.0.1:${HOST_PORTS[searxng]} ✗"; ok=1
  fi
  #: 2) Обёртка: `/health` — служба, к которой приходят по имени в сети.
  if curl -fsS -m 10 "http://127.0.0.1:${HOST_PORTS[mcp-searxng]}/health" >/dev/null 2>&1; then
    echo "[search] mcp-searxng: отвечает на 127.0.0.1:${HOST_PORTS[mcp-searxng]} ✓"
  else
    echo "[search] mcp-searxng: НЕ отвечает на 127.0.0.1:${HOST_PORTS[mcp-searxng]} ✗"; ok=1
  fi
  return $ok
}

case "$ACTION" in
  status)
    status
    ;;
  stop)
    compose stop searxng mcp-searxng
    echo "[search] службы остановлены."
    ;;
  up|*)
    compose up -d searxng mcp-searxng
    sleep 10
    status || { echo "[search] ОСТАНОВ: служба не ответила после старта — смотрите docker logs" >&2; exit 1; }
    echo "[search] имя службы в сети: mcp-searxng:3000 (контракт — менять нельзя)"
    ;;
esac
