///|
/// The published examples: AWS's own signature-calculation page and the two cases every
/// implementation is compared against (`get-vanilla` and the list-users request). A signature
/// is a hex string that looks right when it is wrong, so the intermediate values are asserted
/// as well: the canonical request's hash and the string that is signed locate the mistake.
test "sigv4: the list-users example from the AWS reference" {
  let credential = @bedrock.Credential::new(
    "AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
  )
  let signed = @bedrock.sign(
    credential,
    region="us-east-1",
    service="iam",
    verb="GET",
    host="iam.amazonaws.com",
    path="/",
    query="Action=ListUsers&Version=2010-05-08",
    headers=[
      ("content-type", "application/x-www-form-urlencoded; charset=utf-8"),
    ],
    body_hash=@bedrock.empty_hash(),
    seconds=1_440_938_160L,
  )
  assert_eq(
    @bedrock.payload_hash(@utf8.encode(signed.canonical)[:]),
    "f536975d06c0309214f805bb90ccff089219ecd68b2577efef23edd43b7e1a59",
  )
  assert_eq(
    signed.signature,
    "5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7",
  )
  assert_eq(
    signed.headers[signed.headers.length() - 1],
    (
      "authorization", "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7",
    ),
  )
}

///|
test "sigv4: the get-vanilla case of the test suite" {
  let credential = @bedrock.Credential::new(
    "AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
  )
  let signed = @bedrock.sign(
    credential,
    region="us-east-1",
    service="service",
    verb="GET",
    host="example.amazonaws.com",
    path="/",
    query="",
    headers=[],
    body_hash=@bedrock.empty_hash(),
    seconds=1_440_938_160L,
  )
  assert_eq(
    @bedrock.payload_hash(@utf8.encode(signed.canonical)[:]),
    "bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63",
  )
  assert_eq(
    signed.signature,
    "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31",
  )
}

///|
test "sigv4: a timestamp becomes the two date forms the scope needs" {
  assert_eq(
    @bedrock.amz_dates(1_440_938_160L),
    ("20150830", "20150830T123600Z"),
  )
  // A leap day, and the epoch itself.
  assert_eq(
    @bedrock.amz_dates(1_582_934_400L),
    ("20200229", "20200229T000000Z"),
  )
  assert_eq(@bedrock.amz_dates(0L), ("19700101", "19700101T000000Z"))
}

///|
test "sigv4: a session token is signed with the rest" {
  let credential = @bedrock.Credential::new(
    "AKIDEXAMPLE",
    "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    session_token="token",
  )
  let signed = @bedrock.sign(
    credential,
    region="us-east-1",
    service="bedrock",
    verb="POST",
    host="bedrock-runtime.us-east-1.amazonaws.com",
    path="/model/anthropic.claude/converse",
    query="",
    headers=[("content-type", "application/json")],
    body_hash=@bedrock.payload_hash(@utf8.encode("{}")[:]),
    seconds=1_440_938_160L,
  )
  assert_eq(signed.headers.contains(("x-amz-security-token", "token")), true)
  assert_eq(
    signed.headers[signed.headers.length() - 1].1.contains(
      "SignedHeaders=content-type;host;x-amz-date;x-amz-security-token",
    ),
    true,
  )
}
