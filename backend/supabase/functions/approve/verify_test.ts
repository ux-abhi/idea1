// © Pexilim
import { approvalMessage, verifyApproval } from "./verify.ts";

const toHex = (b: ArrayBuffer) => "\\x" + [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const toB64 = (b: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(b)));

Deno.test("accepts the device's signature and nothing else", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const publicKey = toHex(await crypto.subtle.exportKey("raw", pair.publicKey));
  const other = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const sign = async (key: CryptoKey, hash: string, expires: number) =>
    toB64(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, approvalMessage("a1", hash, expires)));

  const good = await sign(pair.privateKey, "abcd", 1000);
  if (!await verifyApproval(publicKey, "a1", "\\xABCD", 1000, good)) throw new Error("valid signature rejected");
  if (await verifyApproval(publicKey, "a2", "\\xabcd", 1000, good)) throw new Error("other action accepted");
  if (await verifyApproval(publicKey, "a1", "\\xabce", 1000, good)) throw new Error("other payload accepted");
  if (await verifyApproval(publicKey, "a1", "\\xabcd", 1001, good)) throw new Error("other expiry accepted");
  if (await verifyApproval(publicKey, "a1", "\\xabcd", 1000, await sign(other.privateKey, "abcd", 1000))) {
    throw new Error("another key's signature accepted");
  }
  if (await verifyApproval(publicKey, "a1", "\\xabcd", 1000, "not base64!")) throw new Error("garbage accepted");
});

Deno.test("message format matches BlinkKit", () => {
  const text = new TextDecoder().decode(approvalMessage("3f2a-id", "abcdef", 1791720000));
  if (text !== "blink-approve:v1\n3f2a-id\nabcdef\n1791720000") throw new Error(text);
});
