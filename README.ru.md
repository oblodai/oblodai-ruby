<div align="center">

<a href="https://oblodai.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-white.svg">
    <img src="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-black.svg" alt="oblodai" height="52">
  </picture>
</a>

<h3>Официальный Ruby SDK для платёжного шлюза <a href="https://oblodai.com">oblodai</a></h3>

Платежи, выплаты, платёжные ссылки, сплиты, статические кошельки, вебхуки — по одному API-ключу.

<img src="https://img.shields.io/badge/gem-oblodai%201.3.0-E9573F?style=flat-square" alt="gem">
<a href="https://github.com/oblodai/oblodai-ruby/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/oblodai/oblodai-ruby/ci.yml?branch=main&style=flat-square&label=CI" alt="CI"></a>
<img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.1-CC342D?style=flat-square" alt="Ruby version">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-000000?style=flat-square" alt="License: MIT"></a>

[Documentation](https://docs.oblodai.com) · [Dashboard](https://my.oblodai.com) · [Read in English →](README.md)

</div>

---

Официальный Ruby SDK для платёжного шлюза **Oblodai**: приём платежей, выплаты, массовые операции
(батчи), платёжные ссылки, выплатные ссылки (крипточеки), сплиты, статические кошельки, переводы,
вебхуки. Подпись запросов, разбор ответов, типизированные ошибки, идемпотентность и ретраи — из
коробки. Ruby ≥ 3.1 и **ноль рантайм-зависимостей**: используются только `Net::HTTP`, `OpenSSL`,
`JSON` и `SecureRandom` из стандартной библиотеки; каждому маршруту шлюза здесь соответствует метод,
сгенерированный из снимка контракта самого шлюза и проверенный на эталонных ответах, записанных с
живого ядра.

> **Base URL.** По умолчанию `https://api.oblodai.com`. При необходимости переопределите его через
> `base_url:` и передайте свои ключи при инициализации. Схема должна быть `https://`; обычный
> `http://` принимается только для loopback (`http://127.0.0.1:8095`) или с явным разрешением
> небезопасного адреса (`allow_insecure_base_url: true` либо `OBLODAI_ALLOW_INSECURE=1`).

## Установка

```bash
gem install oblodai
```

Или в `Gemfile`:

```ruby
gem "oblodai", "~> 1.3"
```

Требуется Ruby ≥ 3.1. Проверка вебхуков живёт в `oblodai/webhooks`, и ей не нужны ни клиент, ни
API-ключ. Больше ничего не тянется: и гем, и его тесты используют только стандартную библиотеку.

## Где взять ключи

Ключи выпускаются в [личном кабинете](https://my.oblodai.com) → **API keys**. Боевая пара — это
public id `oblodai_<hex>` и секрет `oblodai_live_<hex>`: один унифицированный API-ключ, открывающий
и платёжную, и выплатную сторону. У давних мерчантов два вида могут быть разведены по-старому:
`oblodai_pk_<hex>` (платёжный) и `oblodai_wk_<hex>` (выплатной):

- **платёжным ключом** подписываются счета, платёжные ссылки, кошельки, справочник, настройки и
  документы;
- **выплатным ключом** — всё, что выводит деньги: `payouts.*`, `refunds.*` (включая `resolve`),
  `payout_links.*`, `transfers.*`, `splits.*`, `wallets.refund_blocked_deposit`,
  `settings.*_auto_withdraw`, `settings.*_api_allowlist`, `webhooks.rotate_secret`,
  `webhooks.test("payout", …)`, `sandbox.faucet`, `sandbox.reset`.

Пара песочницы — это public id `test_oblodai_<hex>` и секрет `oblodai_test_<hex>`; она работает с
бесцепочечной копией шлюза и служит **обоими** видами ключа сразу, так что интеграции в песочнице
хватает одной пары. Если боевых пар у вас две, передайте обе — клиент сам выберет нужную для
каждого вызова:

```ruby
client = Oblodai::Client.new(
  public_id: ENV["OBLODAI_PUBLIC_ID"],
  secret: ENV["OBLODAI_SECRET"],
  payout_public_id: ENV["OBLODAI_PAYOUT_PUBLIC_ID"],
  payout_secret: ENV["OBLODAI_PAYOUT_SECRET"]
)
```

Любая опция умеет брать значение из окружения, так что те же четыре переменные настраивают
развёртывание без правки кода. Вызов не тем видом ключа даёт 403 `merchant.wrong_key_kind`; на
маршруте, который принимает любой вид, `prefer_payout_key: true` выбирает для этого вызова
выплатной. Заведение мерчантов (`merchants.create`, `merchants.create_sandbox`) идёт без подписи —
self-hosted шлюз закрывает эти маршруты **админ-токеном онбординга** (`admin_token:` или
`OBLODAI_ADMIN_TOKEN`).

## Быстрый старт

Поля запроса — именованные аргументы, названные ровно так же, как их называет API. Создаём счёт:

```ruby
require "oblodai"

client = Oblodai::Client.new # credentials from the environment

invoice = client.payments.create(
  amount: "25",            # amounts are decimal strings, never floats
  currency: "USDT",        # what you price in — a fiat (USD, EUR, …) or a crypto asset
  network: "tron",         # omit to let the payer choose the network on the pay page
  order_id: "order-1001",  # your reference; idempotent per order_id
  url_callback: "https://shop.example/oblodai/webhook"
)
invoice.url      # the hosted pay page
invoice.address  # where the customer sends the funds
invoice.status   # "created"
```

Чтобы выставить цену в фиате, передайте `amount: "25", currency: "USD", to_currency: "USDT"`:
`currency` — то, в чём вы выставляете счёт, `to_currency` — актив, который отправляет плательщик.
Вывод денег идёт по выплатному ключу:

```ruby
payout = client.payouts.create(
  address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav",
  amount: "10",
  currency: "USDT",
  network: "tron",
  order_id: "payout-1",              # your reference; idempotent per order_id
  idempotency_key: "payout-1"        # your own key survives a process restart
)
payout.uuid
payout.status    # "pending" → … → "confirmed"
```

Готовые к запуску скрипты лежат в [`examples/`](examples): `accept_payment.rb`, `payout.rb`,
`webhook_receiver.rb`.

## Песочница и тестирование

Ключ песочницы работает с бесцепочечной копией шлюза: фейковый баланс из крана, смоделированные
депозиты, настоящие вебхуки. Бизнес-эндпоинты ведут себя ровно так же, как в бою, — меняется только
ключ, а боевой ключ на маршруте песочницы будет отвергнут.

```ruby
sandbox = Oblodai::Client.new(public_id: test_public_id, secret: test_secret)
sandbox.sandbox.faucet(asset: "USDT", amount: "1000")

invoice = sandbox.payments.create(amount: "25", currency: "USDT", network: "tron", order_id: "sandbox-1")

# No amount pays exactly what is due; repeating a txid adds confirmations instead of paying twice.
deposit = sandbox.sandbox.deposit(invoice_id: invoice.uuid)
deposit.txid
deposit.confirmations
```

- `sandbox.faucet` начисляет тестовые деньги, потолок — 1000000 за вызов (выплатной ключ). Передайте
  `idempotency_key:`, если повтор не должен пополнить баланс дважды.
- `sandbox.deposit` оплачивает счёт: без `amount:` платит ровно столько, сколько нужно, любое другое
  значение даёт недоплату или переплату, а `confirmations:` меньше требуемого прогоняет переход
  pending → confirmed. Повтор того же `txid:` добавляет подтверждения, а не платит ещё раз.
- `sandbox.webhooks` показывает доставки вместе с их телами — то, что получил бы ваш обработчик, — а
  `sandbox.replay(delivery_id)` переотправляет терминальную доставку.
- `webhooks.test(kind, **params)` репетирует доставку на любой обработчик, в песочнице и в бою: она
  подписана точно так же, как настоящая, и несёт `test: true` в подписанном теле (и заголовок
  `X-Webhook-Test: true`). Проверяйте `delivery.test?` и никогда не считайте такую доставку деньгами.
- `sandbox.reset` отменяет открытые счета магазина и обнуляет его балансы (выплатной ключ).

## Обзор методов

16 неймспейсов, 107 маршрутов — вся мерчантская поверхность.

| Неймспейс       | Методы                                                                                                                                                                                                   | Маршруты |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| `payments`      | create · info/get · cancel · history/list · batch · qr · services · send_email · resend · public_view · select · public_qr                                                                                | 12       |
| `refunds`       | create · resolve · batch                                                                                                                                                                                  | 3        |
| `payouts`       | create · validate · calculate · info/get · cancel · approve · history/list · mass · batch · services · get/set_fee_config · get/set_refund_fee_config                                                     | 14       |
| `payout_links`  | create · info/get · list · cancel · batch · cheque · claim_preview · claim                                                                                                                                | 8        |
| `payment_links` | create · info/get · list · toggle · public_view · checkout                                                                                                                                                | 6        |
| `transfers`     | to_personal · to_user · batch                                                                                                                                                                             | 3        |
| `batches`       | info/get (прогресс асинхронного батча)                                                                                                                                                                    | 1        |
| `wallets`       | create · qr · block · refund_blocked_deposit                                                                                                                                                              | 4        |
| `webhooks`      | register · rotate_secret · deliveries · test · test_legacy                                                                                                                                                | 7        |
| `documents`     | statement · ledger · balance_certificate · fee_schedule · split_report · batch_report · link_report · wallet_statement · referrals_report · create_job · job_info · job_file · download                    | 13       |
| `splits`        | create_rule · list_rules · delete_rule · get/set_config · get/set_opt_in                                                                                                                                  | 7        |
| `settings`      | set_discount · list_discounts · get/set_accuracy · get/set_auto_refund · list_accepted · set_accepted · get/set_payment_fee_config · list/set/delete_auto_withdraw · list/add/remove/enable_api_allowlist | 17       |
| `account`       | balance · referral · vrcs (чтение и установка)                                                                                                                                                            | 3        |
| `catalog`       | currencies · exchange_rates                                                                                                                                                                               | 2        |
| `sandbox`       | faucet · deposit · webhooks · replay · reset                                                                                                                                                              | 5        |
| `merchants`     | create · create_sandbox (заведение мерчантов; `admin_token:` на self-hosted шлюзе)                                                                                                                        | 2        |

Именованный аргумент, оставленный `nil`, не попадает в тело запроса вместо того, чтобы уехать явным
`null` (шлюз читает и то и другое как «не передано»). Кроме полей запроса каждый метод принимает
`idempotency_key:`, `timeout_ms:`, `deadline_ms:` и `prefer_payout_key:`; опечатка в имени опции
отвергается по имени (`sdk.bad_config`), а не проваливается вглубь SDK.

Поиск по идентификатору принимает голый uuid, любой из именованных аргументов или модель, которую
вернул SDK: `payments.info("uuid")`, `payments.info(uuid: "uuid")`, `payments.info(order_id: "o-1")`,
`payments.info(invoice)`. То же верно для любого id-аргумента (`payout_links.info(link)`,
`batches.info(batch)`, `splits.delete_rule(rule)`).

Синхронные батчи ограничены шлюзом — `payouts.mass` до 100 элементов и `payout_links.batch` до 500,
— и каждый элемент отчитывается сам за себя: `{idx, ok, result, message}`. Асинхронные
(`payments.batch`, `payouts.batch`, `refunds.batch`, `transfers.batch`) принимают до 5000 элементов,
их прогресс опрашивается через `batches.info(id, limit:, offset:)`. Документные маршруты отвечают
вне JSON-конверта и возвращают `Oblodai::FileResult`.

### Модели

Ответы приходят замороженными объектами-моделями, атрибуты которых названы snake_case ровно так же,
как на проводе, плюс `to_h` для сырой формы. Поле, которое шлюз добавит после этого релиза, не
теряется — оно остаётся доступным через `model[:new_field]` и `to_h`.

```ruby
payment = client.payments.info(order_id: "order-1001")
payment.status        # "paid"
payment.paid?         # true for paid / paid_over
payment.amount_paid   # "25.000000" — a String
payment.tx_list.first.txid
payment.to_h          # the exact JSON object the gateway sent, symbol-keyed
```

### Списки

Списочные методы возвращают ленивый `Oblodai::Page`. Он `Enumerable` по всем элементам всех страниц,
а `first_page` отдаёт одну страницу вместе со счётчиками. Пока вы не начали читать, ни одного
запроса не уходит.

```ruby
client.payments.history(limit: 50).each { |payment| puts payment.uuid }   # walks all pages
page = client.payouts.history(status: "confirmed", limit: 50).first_page  # one request
page.items.size
page.paginate.total
page.paginate.has_pages
client.payouts.history(kind: "refund").all(1000)   # at most 1000 items
client.payments.history(limit: 10).first(3)        # stops after the first page
```

### Статусы

- Платёж: `select → created → confirm_check → paid | paid_over | wrong_amount | expired | cancelled`.
  `payment.paid?` истинно для `paid`/`paid_over`; `wrong_amount` (недоплата) ждёт
  `refunds.resolve(uuid:, action: "accept" | "refund")`; `payment.final?` покрывает остальное.
- Выплата: `pending → approved → awaiting_cosign → broadcasting → sent → confirmed | failed | cancelled`.

Для отслеживания смены состояний используйте вебхуки; опрос `info` — только запасной вариант.

### Работа с суммами

`Oblodai::Money.add`, `.subtract`, `.compare`, `.equals?`, `.zero?`, `.negative?`, `.valid?` — точная
десятичная арифметика над строковыми суммами, которыми оперирует API. Никогда не делайте `to_f` над
суммой и не сравнивайте суммы через `<`, `sort` или `max`: `"9" < "10"` истинно для строк и ложно
для денег. Всё, что не является `-?digits[.digits]` длиной не больше 64 символов, поднимает
`Oblodai::ConfigError` (`sdk.bad_amount`), а не `TypeError` из недр хелпера.

## Вебхуки

`webhooks.register(url)` задаёт (или заменяет) эндпоинт и возвращает секрет подписи — он показывается
один раз, поэтому сохраните его туда, откуда его прочитает обработчик. Для проверки не нужны ни
клиент, ни API-ключ, и она всегда идёт по **сырым** байтам: перекодированный разбор подпись не
пройдёт.

```ruby
require "oblodai/webhooks"

post "/oblodai/webhook" do
  body = request.body.read # the RAW bytes — a re-serialized parse will not verify
  delivery = Oblodai::Webhooks.verify_delivery(body, request.env, secret: ENV["OBLODAI_WEBHOOK_SECRET"])
  halt 200 if delivery.test? # a rehearsal: signed like a live one, but no money moved
  event = delivery.event

  case event.type
  when "payment" then mark_order_paid(event.order_id) if event.status == "paid"
  when "payout"  then record_payout(event.uuid, event.status)
  when "wallet"  then credit_customer(event.address, event.payment_amount)
  end
  status 200
end
```

Проверки идут в одном порядке: заголовки, затем HMAC (текущий секрет, затем `previous_secret:`),
затем свежесть, затем тело — MAC раньше часов, чтобы окно свежести не стало оракулом для
неаутентифицированного вызывающего. Доставки старше или новее ±300 с отвергаются (`tolerance:`
меняет окно, `0` его отключает; отрицательное значение — это `ConfigError`, как и пустой `secret:`
или `previous_secret:`).

**Правило кода ответа обработчика.** Отвечайте 401 **только** тогда, когда проверка не прошла:
подделанная или протухшая доставка поднимает `SignatureError`. Аутентичная доставка, тело которой
этот релиз прочитать не может, — это уже `WebhookPayloadError` (`webhook.bad_payload`), ошибка
контракта, а не подписи: событие настоящее, и шлюз повторит доставку, поэтому обработчик, отвечающий
401 на провал подписи, не отвергнет настоящее событие лишь потому, что не смог его разобрать. Тип
события `type`, придуманный более новым шлюзом, тоже не поднимает ошибку: он приходит как
`Oblodai::Models::UnknownEvent` со своим сырым `type` и полями — сузьте тип через
`Oblodai::Webhooks.known_event?(event)`, прежде чем ветвиться по `type`.

Репетиционные доставки (`webhooks.test`, песочница) подписаны точно так же, как боевые, и несут
`test: true` в теле (и заголовок `X-Webhook-Test: true`): проверяйте `delivery.test?` — или
`Oblodai::Webhooks.test_event?(event)`, если у вас на руках только разобранное событие, — и никогда
не считайте такую доставку движением денег. `delivery.id` (`X-Webhook-Id`) стабилен между повторами
— дедуплицируйте по нему; `event.sequence` упорядочивает события
(`Oblodai::Webhooks.stale?(event, last_sequence)` — ложь всякий раз, когда sequence отсутствует).
После `webhooks.rotate_secret` передавайте `previous_secret:` не меньше 26 часов: доставки,
поставленные в очередь до ротации, всю свою жизнь повторов остаются подписанными старым секретом.

## Ошибки

Любая неудача — это `Oblodai::Error` с конвертом ошибки от API. Разбирайте `code` — стабильную
строку `family.reason`, — но никогда не сообщение.

| Класс                       | HTTP           | Когда                                                          |
| --------------------------- | -------------- | ---------------------------------------------------------------- |
| `ValidationError`           | 400            | некорректный запрос или бизнес-правило; `field` называет поле     |
| `AuthenticationError`       | 401            | плохая подпись, неизвестный ключ, расхождение часов, IP не в белом списке |
| `PermissionError`           | 403            | ключ валиден, но здесь нельзя (не тот вид ключа, фича выключена)  |
| `NotFoundError`             | 404            | у этого мерчанта такого объекта нет                               |
| `ConflictError`             | 409            | конфликт состояния                                                |
| `IdempotencyConflictError`  | 409            | `idempotency.key_reused`: тот же ключ, другое тело                |
| `RateLimitError`            | 429            | выставлен `retry_after`                                           |
| `UnavailableError`          | 503            | лежит зависимость; безопасно повторить после паузы                |
| `InternalError`             | другие 5xx     | шлюз упал                                                         |
| `ApiError`                  | всё остальное  | статус ошибки, у которого всё же был конверт                      |
| `TransportError`            | —              | ответа не было вовсе: DNS, TCP, TLS, таймаут, дедлайн             |
| `ConfigError`               | —              | отказ до отправки: плохие опции, нет учётных данных                |
| `ContractError`             | —              | ответ не читается как документированный конверт                    |
| `WebhookPayloadError`       | —              | аутентичный вебхук с нечитаемым телом — не отвечайте 401           |
| `SignatureError`            | —              | вебхук не аутентичен                                              |

Поля: `code`, `message`, `http_status`, `retryable?` (авторитетно — SDK уже повторил то, что
следовало), `retry_after` (в секундах), `request_id` (называйте его поддержке), `field` (на 400),
`synthetic?` (ответ пришёл от прокси, а не от API).

```ruby
begin
  client.payouts.create(**params)
rescue Oblodai::Error => e
  case e.code
  when "payout.insufficient_funds", "payout.funds_maturing" # retryable — the balance may still arrive
    schedule_retry(e.retry_after || 60)
  else
    raise # the SDK already retried what was safe to retry
  end
end
```

Каталог кодов — `Oblodai::Enums::ERROR_CODES`: все 471 кодов ошибок, которыми может ответить шлюз,
поставляются в снимке контракта. Коды, которые стоит обработать в первую очередь:
`payout.insufficient_funds` и `payout.funds_maturing` (оба retryable), `idempotency.key_reused`,
`invoice.not_payable`, `payment.not_found`, `merchant.wrong_key_kind`, `merchant.bad_signature`,
`request.rate_limited`. Поверх них SDK поднимает собственные семейства — всё это до запроса или
вместо него: `sdk.missing_credentials`, `sdk.bad_config`, `sdk.bad_idempotency_key`,
`sdk.idempotency_unsupported`, `sdk.bad_path_param`, `sdk.bad_header`, `sdk.bad_amount`,
`sdk.response_too_large`, `sdk.bad_envelope`; плюс `transport.timeout`, `transport.network`,
`transport.deadline` и семейство вебхуков `webhook.missing_header`, `webhook.bad_signature`,
`webhook.stale_timestamp`, `webhook.bad_payload`.

`e.to_h` / `e.to_json` сохраняют сообщение и выбрасывают сырое тело ответа, так что структурированный
лог никогда не напечатает полезную нагрузку API; для отладки тело по-прежнему доступно через
`e.raw_body`.

## Ретраи, идемпотентность и таймауты

- **Безопасность повтора** не угадывается: `Oblodai::Contract::ROUTES[key].safe` — это собственная
  классификация шлюза «только чтение», поставляемая в снимке контракта.
- Ошибка повторяется только тогда, когда API сказал `retryable: true`. Ответы без конверта API
  (502/503 от прокси) и транспортные сбои повторяются только на читающих маршрутах и на записях с
  ключом идемпотентности. `Retry-After` имеет приоритет над вычисленной паузой.
- **Ключи идемпотентности** проставляются автоматически на создающих маршрутах — один на логический
  вызов, переиспользуемый при каждом повторе, — так что таймаут не может породить вторую выплату.
  Передайте свой `idempotency_key:`, чтобы повторы были безопасны и после перезапуска процесса; на
  маршрутах, которые шлюз не дедуплицирует (включая списочные), SDK отвергает ключ с
  `sdk.idempotency_unsupported`, а не позволяет вам поверить, что повтор безопасен; непригодный ключ
  — это `sdk.bad_idempotency_key`.
- **На вызов:** `idempotency_key:`, `timeout_ms:`, `deadline_ms:`, `prefer_payout_key:`.
  **На клиента:** `timeout_ms:` (на попытку, 30 с), `deadline_ms:` (попытки вместе с паузами, 90 с),
  `retry_policy: { max_retries:, base_delay_ms:, max_delay_ms:, max_retry_after_ms: }`
  (`{ max_retries: 0 }` выключает ретраи). Подсказка `retry_after` показывается вплоть до 24 ч, а
  спит SDK не дольше `max_retry_after_ms` (30 с).
- **Расхождение часов.** На 401 с жалобой на подпись или метку времени SDK читает серверный `Date`,
  переподписывает запрос один раз и сохраняет поправку, только если эта попытка прошла
  аутентификацию. Поправка безопасно разделяется между потоками: откат делается лишь тогда, когда её
  не сдвинул никакой другой вызов.
- **Редиректы никогда не выполняются**: подписанный запрос не должен переигрываться против другого
  origin, поэтому редирект сообщается как ошибка — включая тот, который самостоятельно выполнил
  подставленный HTTP-адаптер.
- **Ограничения размера тела**: 8 МиБ на JSON-маршрутах и 64 МиБ на документных — ответ больше
  становится `sdk.response_too_large`, а не чем-то, что буферизуется в память.
- **Зарезервированные заголовки** выигрывают у пользовательских `headers:` и сравниваются
  без учёта регистра: `X-Public-Id`, `X-Signature`, `X-Timestamp`, `Idempotency-Key`,
  `X-Admin-Token`, `Accept`, `User-Agent`, `Content-Type`, `Content-Length`, `Host`. Заголовок с
  переводом строки или не-ASCII байтом отвергается с `sdk.bad_header` до того, как что-либо уйдёт.

## Конфигурация

| Опция                           | Что делает                                                                     |
| ------------------------------- | -------------------------------------------------------------------------------- |
| `public_id:` / `secret:`        | платёжная пара ключей (используется и для выплат, если выплатной пары нет)        |
| `payout_public_id:` / `payout_secret:` | отдельная выплатная пара ключей                                            |
| `base_url:`                     | origin API; префикс пути сохраняется                                              |
| `allow_insecure_base_url:`      | разрешить обычный `http://` для не-loopback хоста                                 |
| `admin_token:`                  | админ-токен онбординга self-hosted шлюза (только маршруты заведения мерчантов)     |
| `http:`                         | свой HTTP-адаптер: прокси, инструментирование, записанный фейк                    |
| `timeout_ms:`                   | таймаут на попытку (по умолчанию 30 000)                                          |
| `deadline_ms:`                  | бюджет одного вызова вместе с повторами и паузами (по умолчанию 90 000)           |
| `retry_policy:`                 | переопределения политики ретраев; `{ max_retries: 0 }` выключает их                |
| `logger:`                       | что угодно с `debug/info/warn/error(message, fields)`                             |
| `headers:`                      | дополнительные заголовки на каждый запрос (зарезервированные имена игнорируются)   |

| Переменная окружения       | Значение                                                          |
| -------------------------- | ------------------------------------------------------------------ |
| `OBLODAI_PUBLIC_ID`        | public id платёжного ключа                                         |
| `OBLODAI_SECRET`           | секрет платёжного ключа                                            |
| `OBLODAI_PAYOUT_PUBLIC_ID` | public id выплатного ключа                                         |
| `OBLODAI_PAYOUT_SECRET`    | секрет выплатного ключа                                            |
| `OBLODAI_ADMIN_TOKEN`      | админ-токен онбординга self-hosted шлюза                           |
| `OBLODAI_BASE_URL`         | origin API (по умолчанию `https://api.oblodai.com`)                |
| `OBLODAI_LOG`              | `debug` \| `info` \| `warn` \| `error` — включает логгер в stderr   |
| `OBLODAI_ALLOW_INSECURE`   | `1` разрешает обычный `http://` в базовом URL                      |

Явно переданные опции выигрывают у окружения, а пустая переменная считается незаданной. Половина
пары ключей (id без секрета или наоборот) отвергается при создании клиента с `sdk.bad_config`;
отсутствие учётных данных всплывает позже — на первом вызове, которому они нужны.

**Секреты не печатаются.** `WebhookEndpoint#secret`, `WebhookSecretRotated#secret`,
`ApiKeyPair#secret`, `PayoutLink#claim_token` и `PayoutLink#passcode` нормально читаются через свой
аксессор и рендерятся как `"[redacted]"` в `to_h`, `to_json` и `inspect`, так что отладочный лог или
аудит-запись не смогут их унести, — сохраняйте их, читая аксессор, а не сериализуя модель. То же
верно для клиента, его конфига, транспорта и учётных данных, а поля лога, имя которых похоже на
секрет, вычищаются до того, как значение дойдёт до любого логгера.

**Self-hosted или локальный шлюз.** `base_url: "http://127.0.0.1:8095"` работает из коробки; любому
другому http-хосту нужен `allow_insecure_base_url: true` (или `OBLODAI_ALLOW_INSECURE=1`). Префикс
пути в базовом URL сохраняется, поэтому `https://gw.corp/oblodai` доходит до
`https://gw.corp/oblodai/v1/payment` — и подпись покрывает путь вместе с префиксом. Нужен другой
HTTP-стек? Передайте `http:` — что угодно, отвечающее на `call(request, timeout_ms:)` объектом
`Oblodai::HTTP::Response`. Запрос несёт `max_bytes` (потолок для этого маршрута), а ответ может
нести `url`, с которого он пришёл; адаптер, самостоятельно прошедший по редиректу, будет распознан и
отвергнут.

## Снимок контракта

`contract/` экспортируется собственным тестовым набором шлюза: реестр маршрутов (107 маршрутов, у
каждого — собственный флаг `safe` от шлюза, гейт авторизации, поведение идемпотентности и вид
списка), схемы DTO запросов с английскими описаниями полей, все словари и все 471 кодов ошибок,
векторы подписи, эталонные тела ответов, записанные с живого шлюза, и 43 настоящие подписанные
доставки вебхуков. Снимок поставляется вместе с гемом и доступен по `Oblodai.contract_path`.
`lib/oblodai/contract/` сгенерирован из него и никогда не правится руками;
`Oblodai::Contract::CORE_COMMIT`, `EXPORTED_AT` и `CONTRACT_HASH` идентифицируют используемый снимок
(коммит ядра `7ec04293`).

```bash
rake codegen   # regenerate routes.rb, enums.rb, requests.rb after refreshing contract/
rake drift     # CI gate: fail when the committed code is not what codegen produces
```

Машиночитаемая поверхность тоже едет в геме: `Oblodai::Contract::ROUTES` (107 маршрутов),
`Oblodai::Contract::REQUESTS` (каждое документированное поле запроса с типом, словарём и английским
описанием) и `Oblodai::Enums::*` (статусы, сети, плательщики комиссии, типы событий, коды ошибок).
Контрактный слой набора — это гейт полноты, а не выборка: у каждого маршрута должен быть метод,
привязанный к нужному пути, гейту авторизации и поведению идемпотентности, а каждое записанное тело
ответа должно разбираться в модель, поля которой совпадают с проводным форматом ключ в ключ.

## Разработка

```bash
git clone https://github.com/oblodai/oblodai-ruby && cd oblodai-ruby
bundle install
rake ci          # rubocop + contract drift + unit and contract specs
rake yard        # the YARD reference into doc/
OBLODAI_LIVE_URL=http://127.0.0.1:8095 rake spec:live   # the live journeys against a real gateway
gem build oblodai.gemspec
```

Файлы исходников держатся в пределах ~400 строк, а спеки живут рядом с тем, что проверяют. См.
[AGENTS.md](AGENTS.md) — та же поверхность на одной странице, написанная для кодовых агентов;
[CHANGELOG.md](CHANGELOG.md) — что менялось; [MIGRATION-1.3.md](MIGRATION-1.3.md) — переход с 1.2.

## License

MIT — см. [LICENSE](LICENSE).
