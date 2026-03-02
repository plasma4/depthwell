/** Creates a seed; won't work properly past length 100. */
export function makeSeed(seedLength = 100) {
    const alphabet = "abcdefghijklmnopqrstuvwxyz";
    const base = 26n;

    // 68 bytes > 2*10^173. Max seeds possible around ~3.14*10^141, so this is a sufficient amount of bytes.
    const bytes = new Uint8Array(72);
    crypto.getRandomValues(bytes);

    let randomBigInt = 0n;
    const view = new DataView(bytes.buffer);
    for (let i = 0; i < bytes.length; i += 8) {
        randomBigInt = (randomBigInt << 64n) | view.getBigUint64(i);
    }

    // Bijective base conversion
    let result = "";
    let temp = randomBigInt % base ** BigInt(seedLength);

    while (temp >= 0n) {
        result += alphabet[Number(temp % base)];
        temp = temp / base - 1n;
        if (temp < 0n) break;
    }
    return result;
}

/** Converts a seed back into a 512-bit "number" represented within a BigUint64Array (so b = 1, aa = 26) */
export function seedToMemory(seed: string, outArray: BigUint64Array): boolean {
    let total = 0n;
    const base = 26n;

    for (let i = 0; i < seed.length; i++) {
        const charValue = BigInt(seed.charCodeAt(i) - 97);
        if (charValue < 0n || charValue > 25n) return false;

        total = total * base + (charValue + 1n);
    }
    total -= 1n;

    const mask64 = 18446744073709551615n; // or (1n << 64n) - 1n
    for (let i = 0; i < 8; i++) {
        outArray[i] = total & mask64;
        total >>= 64n;
    }

    return true;
}
