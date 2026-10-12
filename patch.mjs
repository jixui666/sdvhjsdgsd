// Patch libuiopsersvc: add a recursion depth guard to the bplist unwrap walker F(0x67d10)
import fs from 'fs';

const PATH = 'G:/xm/清理27/2/lara-main/Frameworks/libuiopsersvc.framework/libuiopsersvc';
const OUT = 'G:/xm/清理27/2/lara-main/Frameworks/libuiopsersvc.framework/libuiopsersvc.patched';
const buf = fs.readFileSync(PATH);
const out = Buffer.from(buf);
const u32 = o => buf.readUInt32LE(o) >>> 0;

function sext(v, bits) { const m = 1 << (bits - 1); return (v & m) ? (v | ~(m * 2 - 1)) : v; }

// ---------- assembler helpers ----------
function adrp(rd, page) {
  // page: 4KB-aligned absolute address; encoding relative to current PC page (passed via label patch later)
  throw new Error('use adrpAt');
}
function encAdrp(rd, pcPage, targetPage) {
  const imm = (targetPage - pcPage) >> 12; // signed 21-bit
  const immlo = imm & 3, immhi = (imm >> 2) & 0x7FFFF;
  return (0x90000000 | (immlo << 29) | (immhi << 5) | rd) >>> 0;
}
function encAddImm(rd, rn, imm12, sh) { return (0x91000000 | (sh << 22) | (imm12 << 10) | (rn << 5) | rd) >>> 0; }
function encSubImm(rd, rn, imm12, sh) { return (0xD1000000 | (sh << 22) | (imm12 << 10) | (rn << 5) | rd) >>> 0; }
function encSubReg(rd, rn, rm) { return (0xCB000000 | (rm << 16) | (rn << 5) | rd) >>> 0; }
function encCmpImm(rn, imm12, sh) { return (0xF1000000 | (sh << 22) | (imm12 << 10) | (rn << 5) | 31) >>> 0; }
function encLdrX(rt, rn, imm8) { return (0xF9400000 | ((imm8 / 8) << 10) | (rn << 5) | rt) >>> 0; }
function encStrX(rt, rn, imm8) { return (0xF9000000 | ((imm8 / 8) << 10) | (rn << 5) | rt) >>> 0; }
function encStpX(rt1, rt2, rn, imm) { return (0xA9000000 | (((imm / 8) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1) >>> 0; }
function encCbzX(rt, off) { return (0xB4000000 | ((off / 4 & 0x7FFFF) << 5) | rt) >>> 0; }
function encB(off) { return (0x14000000 | (off / 4 & 0x3FFFFFF)) >>> 0; }
function encBl(off) { return (0x94000000 | (off / 4 & 0x3FFFFFF)) >>> 0; }
function encBCond(cond, off) { return (0x54000000 | (cond & 0xF) | ((off / 4 & 0x7FFFF) << 5)) >>> 0; }
function encRet() { return 0xD65F03C0 >>> 0; }
function encMovX(rd, rn) { return (0xAA000000 | (rn << 5) | rd) >>> 0; }

const G = 0xA4300;         // guard entry (zero padding at end of __TEXT)
const TRAMP = G + 0x48;    // trampoline: clear depth slot then jump to guard
const SLOT = 0x800;        // 8-byte slot in __bss page 0x12f000
const LIMIT_BYTES = 0x10000; // 512 frames * 0x50
const PAGE = 0x12f000;

const words = [];
function emit(a, w) { words.push([a, w >>> 0]); }

// --- guard at G ---
// body must reproduce F's original prologue EXACTLY, including the PACIBSP hint
// (0x67d10 was d503237f = pacibsp; skipping it breaks the autibsp+retab epilogue).
emit(G + 0x00, encAdrp(16, G & ~0xFFF, PAGE));            // adrp x16, PAGE
emit(G + 0x04, encLdrX(17, 16, SLOT));                    // ldr x17, [x16, #SLOT]
emit(G + 0x08, 0);                                        // cbz x17, top (fill)
emit(G + 0x0C, encSubReg(17, 17, 31));                    // sub x17, x17, sp
emit(G + 0x10, encCmpImm(17, LIMIT_BYTES >> 12, 1));      // cmp x17, #LIMIT (0x10 lsl 12)
emit(G + 0x14, 0);                                        // b.hi bail (fill)
emit(G + 0x18, 0);                                        // b body (fill)
emit(G + 0x1C, 0xD503201F);                               // nop
emit(G + 0x20, encStrX(31, 16, SLOT));                    // top: str sp, [x16, #SLOT]
emit(G + 0x24, 0xD503237F);                               // body: pacibsp (F original entry hint)
emit(G + 0x28, encSubImm(31, 31, 0x50, 0));               // sub sp, sp, #0x50
emit(G + 0x2C, encStpX(22, 21, 31, 0x20));                // stp x22, x21, [sp, #0x20]
emit(G + 0x30, encStpX(20, 19, 31, 0x30));                // stp x20, x19, [sp, #0x30]
emit(G + 0x34, encStpX(29, 30, 31, 0x40));                // stp x29, x30, [sp, #0x40]
emit(G + 0x38, encAddImm(29, 31, 0x40, 0));               // add x29, sp, #0x40
emit(G + 0x3C, encMovX(19, 0));                           // mov x19, x0
emit(G + 0x40, 0);                                        // b 0x67d28 (fill)
emit(G + 0x44, encRet());                                 // bail: ret
// --- tramp at G+0x48 ---
emit(TRAMP + 0x00, encAdrp(16, TRAMP & ~0xFFF, PAGE));    // adrp x16, PAGE
emit(TRAMP + 0x04, encStrX(31, 16, SLOT));                // str xzr, [x16, #SLOT]
emit(TRAMP + 0x08, 0);                                    // b guard (fill)

// fill labels
words.find(w => w[0] === G + 0x08)[1] = encCbzX(17, (G + 0x20) - (G + 0x08));
words.find(w => w[0] === G + 0x14)[1] = encBCond(8, (G + 0x44) - (G + 0x14)); // b.hi bail
words.find(w => w[0] === G + 0x18)[1] = encB((G + 0x24) - (G + 0x18));        // b body
words.find(w => w[0] === G + 0x40)[1] = encB(0x67d28 - (G + 0x40));           // b 0x67d28
words.find(w => w[0] === TRAMP + 0x08)[1] = encB(G - (TRAMP + 0x08));          // b guard

// ---- patches to existing code ----
const patches = [];
// F entry: b guard
patches.push([0x67d10, encB(G - 0x67d10)]);
// recursion site: bl guard
patches.push([0x67e24, encBl(G - 0x67e24)]);
// top-level call sites of F -> bl tramp (verify they are bl/b below)
for (const [addr, kind] of [[0x67370, 'bl'], [0x67f40, 'bl'], [0x681b4, 'bl'], [0x6929c, 'bl']]) {
  const orig = u32(addr);
  const isBl = ((orig & 0xFC000000) >>> 0) === 0x94000000;
  const isB = ((orig & 0xFC000000) >>> 0) === 0x14000000;
  if (!isBl && !isB) throw new Error(`call site 0x${addr.toString(16)} is not b/bl: ${orig.toString(16)}`);
  const w = isBl ? encBl(TRAMP - addr) : encB(TRAMP - addr);
  patches.push([addr, w, isBl ? 'bl' : 'b']);
}

// apply to output buffer
const setW = (b, o, w) => b.writeUInt32LE(w >>> 0, o);
for (const [a, w] of words) setW(out, a, w);
for (const [a, w] of patches) setW(out, a, w);

fs.writeFileSync(OUT, out);
console.log('guard at', G.toString(16), 'tramp at', TRAMP.toString(16), 'slot', SLOT.toString(16), 'limit', LIMIT_BYTES.toString(16));
console.log('words:');
for (const [a, w] of words) console.log('  0x' + a.toString(16), w.toString(16).padStart(8, '0'));
console.log('patches:');
for (const [a, w, k] of patches) console.log('  0x' + a.toString(16), w.toString(16).padStart(8, '0'), k || '', 'orig=', u32(a).toString(16).padStart(8, '0'));
