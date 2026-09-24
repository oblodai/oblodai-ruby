# Examples

| File                   | What it shows                                                                          |
| ---------------------- | -------------------------------------------------------------------------------------- |
| `accept_payment.rb`    | Register the webhook endpoint, create an invoice, read it back, resolve an underpayment |
| `payout.rb`            | Price → dry run → create a payout with your own key; mass payouts; a batch and its wait |
| `sandbox.rb`           | Faucet, a simulated deposit, the deliveries it produced                                  |
| `webhook_receiver.rb`  | Verify a delivery over the raw bytes, deduplicate by event id, drop stale events         |

Every script runs in the test suite against a scripted gateway (`spec/unit/examples_spec.rb`).
Run them against the sandbox:

```bash
export OBLODAI_PUBLIC_ID=test_oblodai_…
export OBLODAI_SECRET=oblodai_test_…
ruby -Ilib examples/accept_payment.rb
```

Against a local gateway, add `OBLODAI_BASE_URL=http://127.0.0.1:8095`.
