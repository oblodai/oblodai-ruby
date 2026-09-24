<div align="center">

<a href="https://oblodai.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-white.svg">
    <img src="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-black.svg" alt="oblodai" height="52">
  </picture>
</a>

<h3>Официальный Ruby SDK для платёжного шлюза <a href="https://oblodai.com">oblodai</a></h3>

Платежи, выплаты, платёжные ссылки, сплиты, статические кошельки, вебхуки — по одному API-ключу.

<img src="https://img.shields.io/badge/gem-oblodai%202.0.0-E9573F?style=flat-square" alt="gem">
<a href="https://github.com/oblodai/oblodai-ruby/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/oblodai/oblodai-ruby/ci.yml?branch=main&style=flat-square&label=CI" alt="CI"></a>
<img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.2-CC342D?style=flat-square" alt="Ruby version">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-000000?style=flat-square" alt="License: MIT"></a>

[Documentation](https://docs.oblodai.com) · [Dashboard](https://my.oblodai.com) · [Read in English →](README.md)

</div>

---

Официальный Ruby SDK для платёжного шлюза **Oblodai**: приём платежей, выплаты, массовые операции
(батчи), платёжные ссылки, выплатные ссылки (крипточеки), сплиты, статические кошельки, переводы,
вебхуки, документы. Подпись запросов, типизированные модели и ошибки, идемпотентность и безопасные
ретраи — из коробки. Ruby ≥ 3.2; единственная рантайм-зависимость — `bigdecimal` (суммы —
`BigDecimal`), всё остальное — стандартная библиотека.

Все методы, модели и перечисления **сгенерированы из OpenAPI-контракта шлюза** — по одному на
операцию API, всего 120 — поверх небольшого рукописного runtime (транспорт, подпись, ретраи,
постраничность, вебхуки). `names.lock` фиксирует публичные имена: имя может пропасть только
намеренно.

> **Base URL.** По умолчанию `https://api.oblodai.com`. При необходимости переопределите его через
> `base_url:` и передайте свои ключи при инициализации. Схема должна быть `https://`; обычный
> `http://` принимается только для loopback (`http://127.0.0.1:8095`) или с явным разрешением
> небезопасного адреса (`allow_insecure_base_url: true` либо `OBLODAI_ALLOW_INSECURE=1`).

## Установка

```bash
gem install oblodai
# or, in a Gemfile: gem "oblodai", "~> 2.0"
```

Ruby ≥ 3.2. Проверка вебхуков живёт в `oblodai/webhooks` и не требует ни клиента, ни API-ключа.
Переходите с 1.x? Читайте [MIGRATION-2.0.md](MIGRATION-2.0.md): каждое старое имя метода и новое.

## Где взять ключи

У мерчанта **один API-ключ**, выдаётся в [кабинете](https://my.oblodai.com) → **API-ключи**:
публичный id `oblodai_<hex>` и секрет `oblodai_live_<hex>`. Он подписывает все подписываемые
маршруты — счета, выплаты, возвраты, ссылки, сплиты, кошельки, настройки, документы, песочницу.
Песочная пара (`test_oblodai_<hex>` / `oblodai_test_<hex>`) управляет копией шлюза без блокчейна.
**Админ-токен онбординга** — совсем другое: он принадлежит оператору шлюза и открывает только
неподписываемый маршрут выдачи песочного магазина (`sandbox.onboard_store`).

```ruby
require "oblodai"

client = Oblodai::Client.new(
  public_id: ENV["OBLODAI_PUBLIC_ID"],
  secret: ENV["OBLODAI_SECRET"]
)
```

Любая опция берёт значение из окружения, если не задана, — те же две переменные настраивают
развёртывание без правки кода.

## Быстрый старт

Методы — `client.<ресурс>.<метод>`; поля запроса — именованные аргументы с именами как в API.
Создать счёт:

```ruby
invoice = client.payments.create(
  amount: "25",            # a decimal String or a BigDecimal — a Float is refused
  currency: "USDT",        # what you price in — a fiat (USD, EUR, …) or a crypto asset
  network: "tron",         # omit to let the payer choose the network on the pay page
  order_id: "order-1001",  # your reference; idempotent per order_id
  url_callback: "https://shop.example/oblodai/webhook"
)
invoice.url      # the hosted pay page
invoice.address  # where the customer sends the funds
invoice.amount   # a BigDecimal
invoice.status   # "created"
```

Чтобы выставить цену в фиате, передайте `amount: "25", currency: "USD", to_currency: "USDT"` —
`currency` определяет, сколько стоит, `to_currency` — чем платят. Выплата тем же ключом:

```ruby
payout = client.payouts.create(
  address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav",
  amount: BigDecimal("10"),
  currency: "USDT",
  network: "tron",
  order_id: "payout-1",        # your reference; idempotent per order_id
  idempotency_key: "payout-1"  # your own key survives a process restart
)
payout.uuid
payout.status    # "pending" → … → "confirmed"
```

Готовые скрипты лежат в [`examples/`](examples): `accept_payment.rb`, `payout.rb`, `sandbox.rb`,
`webhook_receiver.rb`. Они и каждый блок кода этого README выполняются в тестах.

## Песочница и тестирование

Песочный ключ управляет копией шлюза без блокчейна: тестовый баланс из крана, симулированные
депозиты, настоящие вебхуки. Бизнес-эндпоинты ведут себя ровно как в бою — меняется только ключ.

```ruby
sandbox = Oblodai::Client.new(public_id: ENV["OBLODAI_PUBLIC_ID"], secret: ENV["OBLODAI_SECRET"])
sandbox.sandbox.faucet(asset: "USDT", amount: "1000", idempotency_key: "topup-1")

test_invoice = sandbox.payments.create(amount: "25", currency: "USDT", network: "tron", order_id: "sandbox-1")
# No amount pays exactly what is due; repeating a txid adds confirmations instead of paying twice.
deposit = sandbox.sandbox.simulate_deposit(invoice_id: test_invoice.uuid)
deposit.txid
deposit.confirmations
```

- `sandbox.faucet` зачисляет тестовые деньги. Его `idempotency_key:` уходит в тело запроса
  (маршрут дедуплицирует по нему), поэтому повтор не пополнит баланс дважды.
- `sandbox.simulate_deposit` оплачивает счёт: без `amount:` — ровно к оплате, иначе — недоплата или
  переплата; меньше `confirmations:`, чем нужно, проверяет переход pending → confirmed.
- `sandbox.list_webhooks` показывает доставки с телами, `sandbox.replay_webhook` отправляет одну
  повторно, `sandbox.reset` отменяет открытые счета магазина и обнуляет балансы.
- `webhooks.send_test_payment` / `send_test_payout` / `send_test_wallet` / `send_test_conversion`
  репетируют доставку на любой приёмник: подписаны как настоящие, в теле `test: true`.

## Обзор методов

16 пространств имён, 120 методов — по одному на операцию контракта. Имя метода — `operationId`
операции без имени ресурса, в snake_case (`createPayout` → `payouts.create`, `getBatchInfo` →
`batches.get_info`); `Oblodai::Generated::ROUTES` перечисляет все операции по `operationId`.

| Пространство    | Методы                                                                                                    |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| `payments`      | create · get_info · cancel · list_history · get_qr · resolve · send_email · list_services · get_aml_links · get/set_checkout_config |
| `payment_links` | create · get · list · toggle                                                                              |
| `refunds`       | payment · blocked_wallet                                                                                  |
| `payouts`       | create · get_info · cancel · approve · calculate · validate · list_history · list_services · create_mass · create_transfer_batch · transfer_to_personal · transfer_to_user |
| `payout_links`  | create · get · list · cancel · create_batch · get_payout_claim · claim_payout                             |
| `batches`       | create_payment · create_payout · create_refund · get_info                                                 |
| `splits`        | create_rule · list_rules · delete_rule · get/set_config · get/set_recipient_opt_in                        |
| `wallets`       | create · get_qr · block                                                                                   |
| `account`       | get_balance · get_summary · list_exchange_rates                                                           |
| `webhooks`      | register · rotate_secret · set_active · list_deliveries · requeue_delivery · resend_payment · send_test_payment/payout/wallet/conversion · send_legacy_test |
| `settings`      | get/set_accuracy · get/set_auto_convert · get/set_auto_refund · list_discounts · set_discount · list/set_accepted_currencies · get/set_payment_fee_config · get/set_payout_fee_config · get/set_refund_fee_config · list/set/delete_auto_withdraw_rule(s) · list_api_log · configure_vrcs |
| `api_allowlist` | list · add_entry · remove_entry · set_enabled                                                             |
| `referrals`     | get_info                                                                                                  |
| `documents`     | get_statement · get_ledger · get_balance · get_fees · get_batch · get_payment_link · get_split · get_wallet_statement · get_referrals · get_signed · get_payout_link_cheque · create_job · get_job · download_job_file |
| `checkout`      | get · get_qr · select_method · get_onramp · start_onramp · get_public_payment_link · payment_link · list_currencies · get/submit_source_of_funds(_form) |
| `sandbox`       | faucet · simulate_deposit · list_webhooks · replay_webhook · reset · onboard_store                        |

Тело запроса передаётся тремя способами — именованными аргументами, Hash с именами как на проводе
или моделью запроса; аргументы дополняют Hash или модель. Параметры пути — позиционные
(`checkout.get(id)`), параметры запроса у `GET`-маршрутов — именованные. Каждый метод принимает и
пять **опций вызова**: `idempotency_key:`, `timeout:` (секунды на попытку), `max_retries:`,
`extra_headers:` и `request_id:` (уходит как `X-Request-ID`; иначе на вызов генерируется UUID).

```ruby
client.payments.get_info(uuid: invoice.uuid)                                    # keywords
client.payments.get_info({ "order_id" => "order-1001" })                        # a Hash, wire names
client.payments.get_info(Oblodai::Models::LookupRequest.new(order_id: "order-1001")) # a request model
client.payments.get_info(order_id: "order-1001", timeout: 5, max_retries: 0, request_id: "checkout-42")
```

Опечатка в имени аргумента — обычная `ArgumentError` Ruby, до отправки. Аргумент, оставленный
`nil`, не отправляется; немногие поля, где `null` что-то значит (в документации: «An explicit nil
sends null»), отправляют `null`, если передать `nil` явно.

### Модели

Ответы — замороженные объекты `Oblodai::Models::*` с методом-читателем на каждое поле. Суммы —
`BigDecimal`; перечисления — обычные строки, значения названы в `Oblodai::Enums::*`, поэтому
значение, которого этот релиз ещё не знает, разбирается как любое другое; поля новее релиза
сохраняются в `extra`. `to_h` — проводная форма, `inspect` короткий и не показывает секретов.

```ruby
payment = client.payments.get_info(order_id: "order-1001")
payment.status                                  # "paid"
payment.status == Oblodai::Enums::PaymentStatus::PAID
Oblodai::Status.payment_paid?(payment.status)   # true for paid / paid_over
payment.amount                                  # BigDecimal
payment.extra                                   # fields newer than this release, as sent
payment.to_h                                    # the wire form, amounts as decimal strings
```

### Списки

Списочные методы возвращают ленивый `Oblodai::Page`. `each` обходит все элементы всех страниц,
`each_page` (или `by_page`) — все страницы, `first_page` запрашивает одну страницу со счётчиками.
Пока вы не начали читать, запросов нет.

```ruby
client.payments.list_history(limit: 50).each { |item| puts item.uuid }       # every item
client.payouts.list_history(limit: 50).each_page { |page| puts page.size }  # every page
page = client.payouts.list_history(status: "confirmed", limit: 50).first_page # one request
page.items.size
page.total
page.has_pages?
client.payouts.list_history(kind: "refund").all(1000) # at most 1000 items
```

### Долгие операции

Пакеты и выгрузки документов возвращают `Oblodai::Job`: ответ на создание — `job.result`, а
`job.wait` опрашивает, пока задача не завершится — `completed` или `stopped` у пакета, `done`,
`failed` или `expired` у выгрузки, — и возвращает последний ответ. Файл выгрузки — `job.download`.

```ruby
job = client.batches.create_payout(
  payouts: [{ address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav", amount: "5", currency: "USDT",
              network: "tron", order_id: "batch-1-a" }]
)
job.id
info = job.wait(timeout: 600, interval: 5)
info.status # "completed"

report = client.documents.create_job(kind: "ledger", from: "2026-01-01", to: "2026-02-01", format_: "csv")
report.wait
report.download.save("ledger.csv")
```

### Сырой ответ, опции клиента, хуки

```ruby
raw = client.payments.with_raw_response.create(amount: "25", currency: "USDT", order_id: "order-1002")
raw.status      # 200
raw.request_id  # the response's X-Request-ID, else the one the SDK sent
raw.parse       # the PaymentView the method returns otherwise

patient = client.with_options(timeout: 120, max_retries: 5) # a copy; the original is unchanged
patient.documents.get_ledger(from: "2026-01-01", to: "2026-12-31")

hooks = Oblodai::Hooks.new(
  on_request: ->(info) { puts "-> #{info.method} #{info.url} (#{info.request_id})" },
  on_response: ->(info) { puts "<- #{info.status} in #{info.elapsed.round(3)}s" }
)
observed = Oblodai::Client.new(hooks: hooks)
observed.account.get_balance
```

Хуки вызываются по разу на попытку, в вызывающем потоке; подпись и админ-токен в заголовках,
которые они видят, скрыты.

### Статусы

- Платёж: `select → created → confirm_check → paid | paid_over | wrong_amount | expired | cancelled`.
  `Oblodai::Status.payment_paid?` истинно для `paid`/`paid_over`; `wrong_amount` (недоплата) ждёт
  `payments.resolve(uuid:, action: "accept" | "refund")`.
- Выплата: `pending → approved → awaiting_cosign → broadcasting → sent → confirmed | failed | cancelled`.

Об изменениях состояния лучше узнавать из вебхуков; `get_info` — только как запасной опрос.

### Работа с суммами

Суммы в моделях — `BigDecimal`, в запросах — десятичная строка или `BigDecimal`; `Float` там, где
число — деньги, это `sdk.float_amount` до отправки. `Oblodai::Money.add`, `.subtract`, `.compare`,
`.equals?`, `.zero?`, `.negative?` принимают и то и другое и сохраняют наибольшую точность:

```ruby
Oblodai::Money.add("10.000000", BigDecimal("0.5")) # => "10.500000"
Oblodai::Money.compare("9", "10")                  # => -1 (as strings "9" > "10")
```

## Вебхуки

`webhooks.register(url:)` задаёт (или заменяет) эндпоинт и возвращает секрет подписи — он
показывается один раз, сохраните его там, где его прочитает приёмник. Проверке не нужны ни клиент,
ни API-ключ, и она всегда идёт по **сырым** байтам: пересериализованный разбор не пройдёт.

```ruby
require "oblodai/webhooks"

# The raw body and the request headers in, an HTTP status out.
def receive(body, headers, secret)
  delivery = Oblodai::Webhooks.verify_delivery(body, headers, secret: secret)
  return 200 if delivery.test? # a rehearsal: signed like a live one, but no money moved

  case (event = delivery.event)
  when Oblodai::Models::PaymentWebhook then puts "order #{event.order_id}: #{event.status}"
  when Oblodai::Models::PayoutWebhook then puts "payout #{event.uuid}: #{event.status}"
  when Oblodai::Models::WalletWebhook then puts "wallet #{event.address}: +#{event.payment_amount}"
  end
  200
rescue Oblodai::SignatureError
  401 # forged or stale
rescue Oblodai::WebhookPayloadError
  400 # authentic, but unreadable — never 401
end
```

Проверки идут в одном порядке: заголовки, затем HMAC (текущий секрет, затем `previous_secret:`),
затем свежесть, затем тело — MAC раньше часов, чтобы окно свежести не стало оракулом для
неаутентифицированного отправителя. Доставки старше или новее ±300 с отклоняются (`tolerance:`
меняет окно, `0` отключает).

**Правило кодов ответа приёмника.** Отвечайте 401 **только** если проверка не прошла — поддельная
или устаревшая доставка поднимает `SignatureError`. Подлинная доставка, тело которой этот релиз не
смог прочитать, — `WebhookPayloadError` (`webhook.bad_payload`): событие настоящее, и шлюз его
повторит. Вид события, придуманный более новым шлюзом, тоже не падает: он приходит разобранным телом
(замороженный Hash) — `Oblodai::Webhooks.known_event?(event)` различает эти случаи.

Репетиционные доставки несут `test: true` в подписанном теле (и `X-Webhook-Test: true`): проверяйте
`delivery.test?` и никогда не считайте их движением денег. `delivery.id` (`X-Webhook-Id`) стабилен
между повторами — дедуплицируйте по нему; `Oblodai::Webhooks.stale?(event, last_sequence)`
отбрасывает повтор не по порядку. После `webhooks.rotate_secret` передавайте `previous_secret:`
не меньше 26 часов.

## Ошибки

Любая ошибка — `Oblodai::Error` с конвертом ошибки API; её сообщение выглядит как
`[code] текст (request_id=…)` и сразу годится для лога. Ветвитесь по `code` — стабильной строке
`семейство.причина`, — а не по тексту.

| Класс                       | HTTP          | Когда                                                              |
| --------------------------- | ------------- | ------------------------------------------------------------------ |
| `ValidationError`           | 400           | неверный запрос или бизнес-правило; `field` называет поле          |
| `AuthenticationError`       | 401           | неверная подпись, неизвестный ключ, сдвиг часов, IP не в списке    |
| `PermissionError`           | 403           | ключ верный, но здесь нельзя (функция выключена, IP не в списке)   |
| `NotFoundError`             | 404           | нет такого объекта у этого мерчанта                                |
| `ConflictError`             | 409           | конфликт состояния                                                 |
| `IdempotencyConflictError`  | 409           | `idempotency.key_reused`: тот же ключ, другое тело                 |
| `RateLimitError`            | 429           | задан `retry_after`                                                |
| `UnavailableError`          | 503           | недоступна зависимость; безопасно повторить после паузы            |
| `InternalError`             | прочие 5xx    | сбой шлюза                                                         |
| `ApiError`                  | остальное     | статус ошибки, в котором всё же был конверт                        |
| `TransportError`            | —             | ответа нет вовсе: DNS, TCP, TLS, таймаут, дедлайн                  |
| `ConfigError`               | —             | отказ до отправки: неверные опции, Float в сумме, нет ключей       |
| `ContractError`             | —             | ответ не читается как документированный конверт                    |
| `WebhookPayloadError`       | —             | подлинный вебхук с нечитаемым телом — не отвечайте 401             |
| `SignatureError`            | —             | неподлинный вебхук                                                 |

Поля: `code`, `text` (голое описание), `http_status`, `retryable?` (авторитетно — SDK уже повторил
то, что следовало), `retry_after` (секунды), `request_id` (назовите его поддержке), `field` (на
400), `synthetic?` (ответил прокси, а не API).

```ruby
begin
  client.payouts.create(address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav", amount: "10", currency: "USDT",
                        network: "tron", order_id: "payout-2")
rescue Oblodai::Error => e
  warn e.message # "[payout.insufficient_funds] … (request_id=…)"
  raise unless e.retryable?
end
```

Каталог — `Oblodai::Enums::ErrorCode::VALUES`, а документация каждого метода перечисляет коды,
которыми он может ответить. В первую очередь стоит обработать: `payout.insufficient_funds` и
`payout.funds_maturing` (оба повторяемые), `idempotency.key_reused`, `payment.not_found`,
`merchant.bad_signature`, `request.rate_limited`.

Поверх SDK поднимает собственные семейства — все до запроса или вместо него: `sdk.missing_credentials`,
`sdk.bad_config`, `sdk.float_amount`, `sdk.bad_amount`, `sdk.bad_body`, `sdk.bad_idempotency_key`,
`sdk.idempotency_unsupported`, `sdk.bad_path_param`, `sdk.bad_header`, `sdk.response_too_large`,
`sdk.bad_envelope`; плюс `transport.timeout`, `transport.network`, `transport.deadline` и семейство
вебхуков `webhook.missing_header`, `webhook.bad_signature`, `webhook.stale_timestamp`,
`webhook.bad_payload`. `e.to_h` / `e.to_json` не содержат сырого тела ответа; `e.raw_body` его
возвращает.

## Ретраи, идемпотентность и таймауты

- **Безопасность повтора** не угадывается: `Oblodai::Generated::ROUTES[op].safe` берётся из
  `x-retry-safe` контракта (операции только на чтение).
- Ошибка повторяется, только если API ответил `retryable: true`. Ответы без конверта API (502/503
  прокси) и сбои транспорта повторяются только на безопасных маршрутах и на записи с ключом.
  `Retry-After` важнее вычисленной паузы.
- **Ключи идемпотентности** добавляются автоматически на маршрутах, которые шлюз дедуплицирует, —
  один на вызов, один и тот же на всех повторах, — поэтому таймаут не приведёт ко второй выплате.
  Передайте свой `idempotency_key:`, чтобы повтор был безопасен и после перезапуска процесса; на
  маршрутах без дедупликации SDK отклоняет ключ с `sdk.idempotency_unsupported`.
- **Таймауты — в секундах.** На вызов: `timeout:` (на попытку). На клиент: `timeout:` (на попытку,
  30), `deadline:` (весь вызов с повторами и паузами, 90),
  `retry_policy: { max_retries:, base_delay_ms:, max_delay_ms:, max_retry_after_ms: }`
  (`{ max_retries: 0 }` выключает повторы); `max_retries:` вызова переопределяет её.
- **Сдвиг часов.** На 401 о неверной подписи или времени SDK читает `Date` сервера, подписывает
  заново один раз и сохраняет поправку, только если попытка прошла аутентификацию.
- **Редиректы не выполняются**, **тела ограничены** (8 МиБ JSON, 64 МиБ документы), а собственные
  заголовки SDK (`X-Public-Id`, `X-Signature`, `X-Timestamp`, `Idempotency-Key`, `X-Request-ID`,
  `X-Admin-Token`, `Accept`, `User-Agent`, `Content-Type`, `Content-Length`, `Host`) важнее
  заголовков вызывающего; заголовок с переводом строки или не-ASCII байтом — `sdk.bad_header`.

## Конфигурация

```ruby
configured = Oblodai::Client.new(
  base_url: "https://api.oblodai.com",
  timeout: 30,                          # seconds per attempt
  deadline: 90,                         # seconds for the whole call
  retry_policy: { max_retries: 2 },
  headers: { "X-Team" => "checkout" }
)
configured.base_url
```

| Опция                           | Что делает                                                                     |
| ------------------------------- | ------------------------------------------------------------------------------ |
| `public_id:` / `secret:`        | API-ключ мерчанта; подписывает все подписываемые маршруты                      |
| `base_url:`                     | адрес API; префикс пути сохраняется                                            |
| `allow_insecure_base_url:`      | разрешить обычный `http://` для не-loopback хоста                              |
| `admin_token:`                  | админ-токен онбординга своего шлюза (только выдача магазина)                   |
| `http:`                         | свой HTTP-адаптер: всё, что отвечает на `call(request, timeout:)`              |
| `timeout:` / `deadline:`        | секунды на попытку (30) / на весь вызов (90)                                   |
| `retry_policy:`                 | переопределения политики повторов; `{ max_retries: 0 }` выключает повторы      |
| `logger:`                       | любой объект с `debug/info/warn/error(message, fields)`                        |
| `headers:`                      | дополнительные заголовки каждого запроса (зарезервированные игнорируются)      |
| `hooks:`                        | `Oblodai::Hooks.new(on_request:, on_response:)`                                |

| Переменная окружения       | Значение                                                           |
| -------------------------- | ------------------------------------------------------------------ |
| `OBLODAI_PUBLIC_ID`        | публичный id API-ключа                                             |
| `OBLODAI_SECRET`           | секрет API-ключа                                                   |
| `OBLODAI_ADMIN_TOKEN`      | админ-токен онбординга своего шлюза                                |
| `OBLODAI_BASE_URL`         | адрес API (по умолчанию `https://api.oblodai.com`)                 |
| `OBLODAI_LOG`              | `debug` \| `info` \| `warn` \| `error` — включает лог в stderr      |
| `OBLODAI_ALLOW_INSECURE`   | `1` разрешает обычный `http://`                                    |

Явные опции важнее окружения, пустая переменная считается незаданной. Половина пары ключей
отклоняется при создании клиента с `sdk.bad_config`. Клиент, его конфигурация, транспорт и ключи
никогда не печатают секрет, а поля лога с «секретными» именами скрываются до того, как их увидит
любой логгер.

## Сгенерированный код

`lib/oblodai/generated/` — маршруты, перечисления, модели и ресурсы — пишет `tools/sdkgen`
репозитория бэкенда из `services/core/api/openapi.json` шлюза; руками этот код не правится.
`names.lock` перечисляет все публичные `ресурс.метод`; генератор не удалит имя без явного указания.
`make ci` перегенерирует код во временный каталог и падает, если закоммиченный отличается.

## Разработка

```bash
git clone https://github.com/oblodai/oblodai-ruby && cd oblodai-ruby
make ci      # drift check, rubocop, unit + contract + conformance specs, gem build (Ruby in docker if absent)
OBLODAI_BACKEND=../oblodai-backend make ci   # the backend checkout with tools/sdkgen and the conformance suite
OBLODAI_LIVE_URL=http://127.0.0.1:8095 bundle exec rake spec:live   # the live journeys against a real gateway
```

Читайте [AGENTS.md](AGENTS.md) — та же поверхность на одной странице, для агентов-программистов;
[CHANGELOG.md](CHANGELOG.md) — что изменилось; [MIGRATION-2.0.md](MIGRATION-2.0.md) — переход с 1.x.

## License

MIT — see [LICENSE](LICENSE).
