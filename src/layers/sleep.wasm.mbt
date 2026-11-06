///|
/// Wait, in real time. The clock is the runtime's, and a wait that raises on this backend is
/// swallowed: the call it is pacing will report its own outcome anyway.
async fn sleep(ms : Int32) -> Unit noraise {
  @async.sleep(ms)
}
