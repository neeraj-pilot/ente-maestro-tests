import { createHmac } from "node:crypto";

const secret = process.env.TOTP_SECRET;
if (!secret) {
    throw new Error("TOTP_SECRET is required");
}

const timestamp = process.env.TOTP_TIME
    ? Number.parseInt(process.env.TOTP_TIME, 10)
    : Math.floor(Date.now() / 1000);
if (!Number.isSafeInteger(timestamp) || timestamp < 0) {
    throw new Error("TOTP_TIME must be a non-negative integer");
}

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
let buffer = 0;
let bits = 0;
const bytes = [];
for (const character of secret.toUpperCase().replaceAll("=", "")) {
    const value = alphabet.indexOf(character);
    if (value < 0) {
        throw new Error(`Invalid base32 character: ${character}`);
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
        bits -= 8;
        bytes.push((buffer >> bits) & 0xff);
    }
}

const counter = Buffer.alloc(8);
counter.writeBigUInt64BE(BigInt(Math.floor(timestamp / 30)));
const digest = createHmac("sha1", Buffer.from(bytes)).update(counter).digest();
const offset = digest[digest.length - 1] & 0x0f;
const binary =
    ((digest[offset] & 0x7f) << 24) |
    (digest[offset + 1] << 16) |
    (digest[offset + 2] << 8) |
    digest[offset + 3];

process.stdout.write(String(binary % 1_000_000).padStart(6, "0"));
