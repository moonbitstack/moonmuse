///|
/// The JSON-schema type of a tool parameter. Koog's `ToolParameterType` is a
/// sealed hierarchy; this is a faithful 1:1 sum. `TList`/`TObject`/`TAnyOf` recur.
/// Source: agents/agents-tools/.../tools/ToolDescriptor.kt.
pub(all) enum ToolParameterType {
  TString
  TInteger
  TFloat
  TBoolean
  TNull
  TEnum(Array[String])
  TList(ToolParameterType)
  TObject(
    properties~ : Array[ToolParameterDescriptor],
    required~ : Array[String]
  )
  TAnyOf(Array[ToolParameterDescriptor])
} derive(Eq, Debug)

///|
/// One named tool parameter: its name, human description, and schema type.
/// Source: agents/agents-tools/.../tools/ToolDescriptor.kt.
pub(all) struct ToolParameterDescriptor {
  name : String
  description : String
  ptype : ToolParameterType
} derive(Eq, Debug)

///|
/// A tool's schema as the LLM is shown it (Koog `ToolDescriptor`): the name it is
/// called by, a description, and the required / optional parameter lists.
/// Source: agents/agents-tools/.../tools/ToolDescriptor.kt.
pub(all) struct ToolDescriptor {
  name : String
  description : String
  required_parameters : Array[ToolParameterDescriptor]
  optional_parameters : Array[ToolParameterDescriptor]
} derive(Eq, Debug)

///|
/// This parameter type as a JSON Schema fragment — what a tool/function
/// definition advertises to the model, and what a structured-output request
/// constrains the reply to. Koog derives the schema from the Kotlin type via
/// kotlinx.serialization; with no reflection here it is rendered from the explicit
/// `ToolParameterType`.
pub fn ToolParameterType::to_json_schema(self : ToolParameterType) -> Json {
  match self {
    TString => { "type": "string" }
    TInteger => { "type": "integer" }
    TFloat => { "type": "number" }
    TBoolean => { "type": "boolean" }
    TNull => { "type": "null" }
    TEnum(values) => {
      let vs : Array[Json] = []
      for v in values {
        vs.push(v.to_json())
      }
      { "type": "string", "enum": Json::array(vs) }
    }
    TList(inner) => { "type": "array", "items": inner.to_json_schema() }
    TObject(properties~, required~) => {
      let props : Map[String, Json] = Map([])
      for p in properties {
        props[p.name] = p.ptype.to_json_schema()
      }
      let req : Array[Json] = []
      for r in required {
        req.push(r.to_json())
      }
      {
        "type": "object",
        "properties": Json::object(props),
        "required": Json::array(req),
      }
    }
    TAnyOf(descs) => {
      let arr : Array[Json] = []
      for d in descs {
        arr.push(d.ptype.to_json_schema())
      }
      { "anyOf": Json::array(arr) }
    }
  }
}

///|
/// A callable tool. Koog's `Tool<TArgs, TResult>` derives its schema from the
/// argument type via kotlinx.serialization + a `TypeToken`; MoonBit has no
/// reflection, so a tool states its `descriptor()` explicitly and `execute_raw`
/// decodes the JSON arguments, runs, and encodes the result to the string the
/// model is shown — Koog's `decodeArgs` + `execute` + `encodeResultToString`
/// collapsed to the `SimpleTool<TArgs> : String` shape.
/// Source: agents/agents-tools/.../tools/{ToolBase,Tool,SimpleTool}.kt.
pub(open) trait Tool {
  fn descriptor(Self) -> ToolDescriptor
  fn execute_raw(Self, args : Json) -> String raise
}

///|
/// A set of tools addressable by name. Koog `ToolRegistry`.
/// Source: agents/agents-tools/.../tools/ToolRegistry.kt.
pub(all) struct ToolRegistry {
  tools : Array[&Tool]
}

///|
/// An empty registry (Koog `ToolRegistry.EMPTY`).
pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: [], }
}

///|
/// Register a tool and return the registry, so registration chains (MoonBit has
/// no receiver-lambda DSL for Koog's `ToolRegistry { tool(...) }`).
pub fn ToolRegistry::add(self : ToolRegistry, tool : &Tool) -> ToolRegistry {
  self.tools.push(tool)
  self
}

///|
/// The tool named `name`, or `None` (Koog `getToolOrNull`).
pub fn ToolRegistry::get_tool(self : ToolRegistry, name : String) -> &Tool? {
  for t in self.tools {
    if t.descriptor().name == name {
      return Some(t)
    }
  }
  None
}

///|
/// Every registered tool's descriptor — what a request advertises to the model.
pub fn ToolRegistry::descriptors(self : ToolRegistry) -> Array[ToolDescriptor] {
  let ds = []
  for t in self.tools {
    ds.push(t.descriptor())
  }
  ds
}

///|
pub extend ToolDescriptor with Debug::{to_repr}

///|
pub extend ToolDescriptor with Eq::{not_equal, equal}

///|
pub extend ToolParameterDescriptor with Debug::{to_repr}

///|
pub extend ToolParameterDescriptor with Eq::{not_equal, equal}

///|
pub extend ToolParameterType with Debug::{to_repr}

///|
pub extend ToolParameterType with Eq::{not_equal, equal}
