// © Pexilim
// The red-approval signature check, kept free of server code so it can be tested on its own.

export const MAX_TTL_SECONDS = 300;

/** The exact bytes a device signs; mirrors BlinkAction.approvalMessage in BlinkKit. */
export function approvalMessage(actionID: string, payloadHashHex: string, expires: number) {
  return new TextEncoder().encode(`blink-approve:v1\n${actionID}\n${payloadHashHex}\n${expires}`);
}

/** PostgREST returns bytea as "\x<hex>". */
export function hex(value: string): string {
  const h = value.startsWith("\\x") ? value.slice(2) : value;
  if (!/^(?:[0-9a-f]{2})+$/i.test(h)) throw new Error("bad hex");
  return h.toLowerCase();
}

function bytes(hexString: string) {
  return Uint8Array.from(hexString.match(/../g)!, (b) => parseInt(b, 16));
}

/** True only for a valid P-256 signature (raw r‖s, base64) over this action, payload hash and expiry. */
export async function verifyApproval(publicKey: string, actionID: string, payloadHash: string, expires: number,
                                     signature: string): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey("raw", bytes(hex(publicKey)), { name: "ECDSA", namedCurve: "P-256" },
      false, ["verify"]);
    const sig = Uint8Array.from(atob(signature), (c) => c.charCodeAt(0));
    return await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig,
      approvalMessage(actionID, hex(payloadHash), expires));
  } catch {
    return false;
  }
}
