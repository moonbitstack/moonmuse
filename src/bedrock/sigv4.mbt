///|
/// Signature Version 4, the way AWS authenticates a request: hash the body, build a canonical
/// form of the request, sign it with a key derived from the secret by HMAC in four steps, and
/// put the result in `Authorization`.
///
/// The pieces are separate functions because each one is where a mistake hides: the canonical
/// request is a summary of the headers that are signed, so a header added after signing is a
/// signature that fails; the key derivation is a chain, so one wrong step still produces a
/// plausible-looking hex string.
///
/// The algorithm is `AWS4-HMAC-SHA256`; the reference is the AWS General Reference, "Signature
/// Version 4 signing process", and the test vectors are its published examples.

///|
/// The credential a request is signed with. `session_token` is present for temporary
/// credentials, which is what an instance role hands out.
pub struct Credential {
  access_key : String
  secret_key : String
  session_token : String?
}

///|
/// A credential from a key pair.
pub fn Credential::new(
  access_key : String,
  secret_key : String,
  session_token? : String,
) -> Credential {
  { access_key, secret_key, session_token, }
}

///|
/// The SHA-256 of a body, in the hex lowercase the signature writes.
pub fn payload_hash(body : BytesView) -> String {
  hex_of(@sha2.hash(body, kind=@sha2.Sha256))
}

///|
/// The hash of an empty body, which is what a GET sends.
pub fn empty_hash() -> String {
  payload_hash(Bytes::new(0)[:])
}

///|
/// The `x-amz-date` value and the scope date for a Unix time in seconds. The two are the same
/// day in UTC written two ways, and both go into the signature.
pub fn amz_dates(seconds : Int64) -> (String, String) {
  let days = floor_div(seconds, 86400L)
  let within = seconds - days * 86400L
  let (year, month, day) = civil_from_days(days)
  let date = pad(year, 4) + pad(month, 2) + pad(day, 2)
  let stamp = date +
    "T" +
    pad(floor_div(within, 3600L), 2) +
    pad(floor_div(within % 3600L, 60L), 2) +
    pad(within % 60L, 2) +
    "Z"
  (date, stamp)
}

///|
/// The four-step key: date, region, service, then the string "aws4_request".
pub fn signing_key(
  secret_key : StringView,
  date : StringView,
  region : StringView,
  service : StringView,
) -> Bytes {
  let k_date = hmac_sha256(
    @utf8.encode("AWS4" + secret_key.to_owned())[:],
    @utf8.encode(date)[:],
  )
  let k_region = hmac_sha256(k_date[:], @utf8.encode(region)[:])
  let k_service = hmac_sha256(k_region[:], @utf8.encode(service)[:])
  hmac_sha256(k_service[:], @utf8.encode("aws4_request")[:])
}

///|
/// One HMAC-SHA256, which the key chain and the signature both use.
pub fn hmac_sha256(key : BytesView, data : BytesView) -> Bytes {
  @hmac.mac(key, data, fn() { @sha2.Hasher::new(kind=@sha2.Sha256) })
}

///|
/// The canonical request: the form the signature is taken over. Headers are ordered by code
/// unit, which is what the specification says and what `String::lexical_compare` does —
/// `String::compare` is shortlex, so it orders by length first and would put `host` before
/// `content-type`. `headers` must already be the
/// ones that will be signed, sorted and lower-cased; the signer adds `host`, `x-amz-date` and
/// the content hash, so a caller does not forget them.
pub fn canonical_request(
  verb : String,
  path : String,
  query : String,
  headers : Array[(String, String)],
  signed : Array[String],
  body_hash : String,
) -> String {
  let sorted = headers.copy()
  sorted.sort_by(fn(a, b) { a.0.lexical_compare(b.0) })
  let canonical_headers = StringBuilder()
  for pair in sorted {
    canonical_headers.write_string(pair.0.to_lower())
    canonical_headers.write_string(":")
    canonical_headers.write_string(pair.1.trim().to_owned())
    canonical_headers.write_string("\n")
  }
  verb +
  "\n" +
  path +
  "\n" +
  query +
  "\n" +
  canonical_headers.to_string() +
  "\n" +
  signed.join(";") +
  "\n" +
  body_hash
}

///|
/// The string that is signed: the algorithm, the stamp, the scope and the hash of the
/// canonical request.
pub fn string_to_sign(
  stamp : String,
  date : String,
  region : String,
  service : String,
  canonical : String,
) -> String {
  "AWS4-HMAC-SHA256\n" +
  stamp +
  "\n" +
  date +
  "/" +
  region +
  "/" +
  service +
  "/aws4_request\n" +
  payload_hash(@utf8.encode(canonical)[:])
}

///|
/// What a signed request carries: the headers to send, `authorization` among them.
pub struct Signed {
  headers : Array[(String, String)]
  canonical : String
  string_to_sign : String
  signature : String
}

///|
/// Sign a request. `headers` are the ones the caller is sending beyond the three this adds;
/// every one of them is signed, so what is signed is what is sent.
pub fn sign(
  credential : Credential,
  region~ : String,
  service~ : String,
  verb~ : String,
  host~ : String,
  path~ : String,
  query~ : String,
  headers~ : Array[(String, String)],
  body_hash~ : String,
  seconds~ : Int64,
) -> Signed {
  let (date, stamp) = amz_dates(seconds)
  let all = [("host", host), ("x-amz-date", stamp)]
  let merged = []
  for pair in [..headers, ..all] {
    merged.push((pair.0.to_lower(), pair.1))
  }
  match credential.session_token {
    Some(token) => merged.push(("x-amz-security-token", token))
    None => ()
  }
  let signed = merged.map(pair => pair.0)
  signed.sort_by(fn(a, b) { a.lexical_compare(b) })
  let canonical = canonical_request(
    verb, path, query, merged, signed, body_hash,
  )
  let to_sign = string_to_sign(stamp, date, region, service, canonical)
  let key = signing_key(
    credential.secret_key[:],
    date[:],
    region[:],
    service[:],
  )
  let signature = hex_of(hmac_sha256(key[:], @utf8.encode(to_sign)[:]))
  let authorization = "AWS4-HMAC-SHA256 Credential=" +
    credential.access_key +
    "/" +
    date +
    "/" +
    region +
    "/" +
    service +
    "/aws4_request, SignedHeaders=" +
    signed.join(";") +
    ", Signature=" +
    signature
  {
    headers: [..merged, ("authorization", authorization)],
    canonical,
    string_to_sign: to_sign,
    signature,
  }
}

///|
/// Bytes as lowercase hexadecimal.
fn hex_of(data : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for byte in data {
    let value = byte.to_int()
    let high = value / 16
    let low = value % 16
    out.write_string(digits.exact_view(start=high, end=high + 1).to_owned())
    out.write_string(digits.exact_view(start=low, end=low + 1).to_owned())
  }
  out.to_string()
}

///|
/// Division that rounds towards negative infinity, which is what a day boundary needs before
/// 1970.
fn floor_div(value : Int64, by : Int64) -> Int64 {
  let quotient = value / by
  if value % by != 0 && (value < 0) != (by < 0) {
    quotient - 1
  } else {
    quotient
  }
}

///|
/// Days since 1970-01-01 to a Gregorian date, by Howard Hinnant's civil-from-days. A calendar
/// is not worth a dependency for four numbers.
fn civil_from_days(days : Int64) -> (Int64, Int64, Int64) {
  let shifted = days + 719_468L
  let era = floor_div(shifted, 146_097L)
  let day_of_era = shifted - era * 146_097L
  let year_of_era = (
      day_of_era -
      day_of_era / 1460L +
      day_of_era / 36_524L -
      day_of_era / 146_096L
    ) /
    365L
  let year = year_of_era + era * 400L
  let day_of_year = day_of_era -
    (365L * year_of_era + year_of_era / 4L - year_of_era / 100L)
  let month_prime = (5L * day_of_year + 2L) / 153L
  let day = day_of_year - (153L * month_prime + 2L) / 5L + 1L
  let month = if month_prime < 10L {
    month_prime + 3L
  } else {
    month_prime - 9L
  }
  let year = if month <= 2L { year + 1L } else { year }
  (year, month, day)
}

///|
/// A number in `width` digits, zero-padded.
fn pad(value : Int64, width : Int32) -> String {
  let text = value.to_string()
  let out = StringBuilder()
  for i = 0; i < width - text.length(); i = i + 1 {
    out.write_char('0')
    let _ = i
  }
  out.write_string(text)
  out.to_string()
}
