///|
/// A sample tool used by the tests: add two integers from the JSON args.
struct AddTool {}

///|
impl Tool for AddTool with fn descriptor(_self) {
  {
    name: "add",
    description: "add two integers a and b",
    required_parameters: [
      { name: "a", description: "first addend", ptype: TInteger, },
      { name: "b", description: "second addend", ptype: TInteger, },
    ],
    optional_parameters: [],
  }
}

///|
impl Tool for AddTool with fn execute_raw(_self, args) {
  (json_int(args, "a") + json_int(args, "b")).to_string()
}

///|
fn json_int(j : Json, key : String) -> Int32 {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
test "a registered tool advertises its descriptor and runs on JSON args" {
  let reg = ToolRegistry::new().add(AddTool::{ })
  assert_eq(reg.descriptors().length(), 1)
  let d = reg.descriptors()[0]
  assert_eq(d.name, "add")
  assert_eq(d.required_parameters.length(), 2)
  assert_eq(d.required_parameters[0].ptype, TInteger)
  let tool = reg.get_tool("add").unwrap()
  let out = tool.execute_raw({ "a": 2, "b": 3 }) catch {
    _ => fail("tool raised")
  }
  assert_eq(out, "5")
  assert_true(reg.get_tool("missing") is None)
}

///|
test "nested parameter types round-trip through Eq/Debug" {
  let t : ToolParameterType = TObject(
    properties=[{ name: "xs", description: "a list", ptype: TList(TString), }],
    required=["xs"],
  )
  assert_eq(
    t,
    TObject(
      properties=[{ name: "xs", description: "a list", ptype: TList(TString), }],
      required=["xs"],
    ),
  )
}
