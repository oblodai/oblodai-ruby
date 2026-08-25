# Examples

| File                   | What it shows                                                                     |
| ---------------------- | --------------------------------------------------------------------------------- |
| `accept_payment.rb`    | Create an invoice, read it back, resolve an underpayment, list history             |
| `payout.rb`            | Price → dry run → create a payout with your own idempotency key; mass payouts      |
| `webhook_receiver.rb`  | Verify a delivery over the raw bytes, deduplicate by delivery id, drop stale events |

Run them against the sandbox:

```bash
export OBLODAI_PUBLIC_ID=test_…
export OBLODAI_SECRET=…
ruby -Ilib examples/accept_payment.rb
```

Against a local gateway, add `OBLODAI_BASE_URL=http://127.0.0.1:8095`.
