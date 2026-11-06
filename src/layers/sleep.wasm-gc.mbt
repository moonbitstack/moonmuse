///|
/// Wait, in real time. On this backend a sleep can be cancelled, which raises; the wait a
/// retry or a rate limit performs has nothing to add to that, so it stops early and lets the
/// next attempt report the cancellation.
async fn sleep(ms : Int32) -> Unit noraise {
  @async.sleep(ms) catch {
    _ => ()
  }
}
