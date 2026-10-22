# Проект `search`: свой инстанс SearXNG и своя MCP-обёртка. Свой Makefile — чтобы проект можно было
# поднять и проверить без воркспейса. Логика живёт в лончере, цели её не дублируют.
.PHONY: ci up status stop restart check

up:
	bash search-up.sh up

status:
	bash search-up.sh status

stop:
	bash search-up.sh stop

restart: stop up

#: Офлайн-проверка: композ обязан РАЗБИРАТЬСЯ настоящим парсером (демон не нужен), а настройки инстанса —
#: быть корректным YAML с ожидаемым набором движков.
check:
	@SEARXNG_SECRET=__check__ docker compose -f compose.search.yaml config -q \
	  && python3 -c "import yaml,sys; d=yaml.safe_load(open('searxng/settings.yml', encoding='utf-8')); \
	  assert d['use_default_settings']['engines']['keep_only'], 'в настройках нет keep_only'; \
	  print('[search] композ разбирается, настройки инстанса на месте ✓')"

#: То же, что гоняет CI: композ и настройки.
ci: check
