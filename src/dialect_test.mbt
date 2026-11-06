///|
/// The block ordinal a stream writer puts on the wire: one per content block, starting at
/// zero, so a reader can tell a text block from the tool block after it.
test "turn: block ordinals advance one per block" {
  let turn = @moonmuse.Turn::new()
  assert_eq(turn.next_block(), 0)
  assert_eq(turn.next_block(), 1)
  assert_eq(turn.next_block(), 2)
  assert_eq(turn.block, 3)
}

///|
test "turn: scratch values are per key and default to empty" {
  let turn = @moonmuse.Turn::new()
  assert_eq(turn.slot("missing"), "")
  turn.add_slot("calls", "a")
  turn.add_slot("calls", "b")
  assert_eq(turn.slot("calls"), "ab")
  assert_eq(turn.num("hits"), 0)
  assert_eq(turn.add_num("hits", 3), 3)
}

///|
test "route: a wildcard matches one run of characters" {
  let route = @moonmuse.Route::new(
    @moonmuse.Embed,
    "POST",
    "/v1beta/models/*:embedContent",
  )
  assert_eq(
    route.matches("POST", "/v1beta/models/text-embedding-004:embedContent"),
    true,
  )
  assert_eq(route.matches("POST", "/v1beta/models/x:generateContent"), false)
  assert_eq(route.matches("GET", "/v1beta/models/x:embedContent"), false)
}
