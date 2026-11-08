// The site's converter, checked the way the page uses it: one body in, the other three out.
//
// The build is the subject, so the module is imported from where `moon build` put it. Run after
//     moon build src/examples/07-convert --target js --release
// from the repository root:
//     node scripts/check-convert.mjs
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const built = join(
  root,
  "_build/js/release/build/examples/07-convert/07-convert.js",
);
const { convert } = await import(pathToFileURL(built).href);

const openai = `{
  "model": "gpt-4o-mini",
  "messages": [
    {"role": "system", "content": "Answer in one sentence."},
    {"role": "user", "content": "Why is the sky blue?"}
  ],
  "temperature": 0.2,
  "max_tokens": 256
}`;

const failures = [];
function check(label, condition, detail) {
  if (condition) {
    console.log("  ok   " + label);
  } else {
    failures.push(label + (detail ? ": " + detail : ""));
    console.log("  FAIL " + label + (detail ? ": " + detail : ""));
  }
}

const run = (source, target, path, body) =>
  JSON.parse(convert(source, target, path, body));

const anthropic = run("openai", "anthropic", "/v1/chat/completions", openai);
check("openai reads and anthropic writes", anthropic.ok, JSON.stringify(anthropic));
check(
  "anthropic keeps the system prompt out of the message list",
  anthropic.body.system === "Answer in one sentence." &&
    anthropic.body.messages.length === 1,
);
check(
  "anthropic requires max_tokens, so it is written",
  anthropic.body.max_tokens === 256,
);

const gemini = run("openai", "gemini", "/v1/chat/completions", openai);
check("gemini is written", gemini.ok, JSON.stringify(gemini));
check(
  "gemini puts the model in the path and the knobs under generationConfig",
  // The model travels with the request: it is the source's name, in the place Gemini keeps it.
  gemini.path === "/models/gpt-4o-mini:generateContent" &&
    gemini.body.generationConfig.maxOutputTokens === 256 &&
    gemini.body.contents[0].parts[0].text === "Why is the sky blue?",
  gemini.path,
);

const ollama = run("openai", "ollama", "/v1/chat/completions", openai);
check("ollama is written", ollama.ok, JSON.stringify(ollama));
check(
  "ollama nests the options and turns streaming off",
  ollama.body.options.num_predict === 256 && ollama.body.stream === false,
);

// A round trip: the same conversation written and read back has to survive.
const back = run(
  "anthropic",
  "openai",
  "/v1/messages",
  JSON.stringify(anthropic.body),
);
check("a body round-trips back to openai", back.ok, JSON.stringify(back));
const original = JSON.parse(openai);
check(
  "the round trip keeps the conversation",
  back.body.messages[1].content === original.messages[1].content &&
    back.body.temperature === 0.2 &&
    back.body.max_tokens === 256,
  JSON.stringify(back.body.messages),
);

// Errors come back as data, because the page shows them under the pane that was edited.
const broken = run("openai", "anthropic", "/v1/chat/completions", "{ nope");
check(
  "a body that is not JSON is refused, not thrown",
  broken.ok === false && broken.error.length > 0,
  JSON.stringify(broken),
);

const unknown = run("nope", "anthropic", "/x", openai);
check(
  "an unknown format is refused",
  unknown.ok === false && /no format/.test(unknown.error),
  JSON.stringify(unknown),
);

if (failures.length) {
  console.log("\n" + failures.length + " failed");
  process.exit(1);
}
console.log("\nthe converter agrees with itself");
