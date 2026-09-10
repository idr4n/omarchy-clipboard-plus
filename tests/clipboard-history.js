#!/usr/bin/env node

const assert = require("node:assert/strict");
const history = require("../ClipboardHistory.js");

function parsedEntries(values) {
  const result = history.parseHistory(JSON.stringify(values));
  assert.equal(result.status, "ok");
  return result.entries;
}

assert.equal(history.utf8ByteLength("plain"), 5);
assert.equal(history.utf8ByteLength("é"), 2);
assert.equal(history.utf8ByteLength("😀"), 4);
assert.equal(history.utf8ByteLength("\ud800"), 3);

assert.equal(history.detectColor("#a954f4"), "#A954F4");
assert.equal(history.detectColor(" 3bd671 "), "#3BD671");
assert.equal(history.detectColor("color #a954f4"), "");
assert.equal(history.detectColor("#abcd"), "#AABBCCDD");
assert.equal(history.detectColor("#abc"), "#AABBCC");
assert.equal(history.detectColor("#123f"), "#112233");

// Each expression exercises a distinct CSS syntax or conversion boundary.
for (const [expression, expected] of [
  ["RGB(122, 162, 247)", "#7AA2F7"],
  ["rgba(100%, 0%, 0%, 50%)", "#FF000080"],
  ["rgb(100% 0 0 / .5)", "#FF000080"],
  ["rgba(255 0 0)", "#FF0000"],
  ["rgb(1e2 0 0)", "#640000"],
  ["hsl(120, 100%, 50%)", "#00FF00"],
  ["hsla(.5turn 100% 50% / 25%)", "#00FFFF40"],
  ["hsl(-100grad 100% 50%)", "#8000FF"],
  [`hsl(${Math.PI}rad 100% 50%)`, "#00FFFF"],
  ["hsl(720deg 100% 50%)", "#FF0000"],
  ["hsl(1e308deg 0% 100%)", "#FFFFFF"],
  ["rgba(255, 0, 0, 0)", "#FF000000"],
]) {
  assert.equal(history.detectColor(expression), expected, expression);
}

const alphaLast = history.colorDetails("#10203080");
assert.deepEqual(
  [alphaLast.red, alphaLast.green, alphaLast.blue, alphaLast.alpha],
  [16 / 255, 32 / 255, 48 / 255, 128 / 255],
);
assert.equal(history.colorDetails("rgba(255 0 0 / .5)").alpha, 0.5);

// Converted display expressions must still describe the same color, including
// near-black/near-white values where naive HSL division loses precision.
for (const expression of [
  "#7aa2f780",
  "rgba(12.5, 27.25, 200.5, .125)",
  "hsl(0 100% 1%)",
  "rgb(255 254.99999999999997 255)",
  "#000",
  "#fff",
  "rgba(0, 0, 0, 0)",
]) {
  const details = history.colorDetails(expression);
  for (const rendered of [details.rgb, details.hsl]) {
    const converted = history.colorDetails(rendered);
    assert.ok(converted, `invalid color preview: ${rendered}`);
    for (const channel of ["red", "green", "blue", "alpha"]) {
      assert.ok(
        Math.abs(converted[channel] - details[channel]) < 1 / 255,
        `${expression} changed ${channel} in ${rendered}`,
      );
    }
  }
}

for (const invalid of [
  "#12", "#12345", "#1234567", "abc", "abcd", "12345678",
  "color: #abc", "use rgb(1,2,3) here",
  "rgb(256,0,0)", "rgb(-1 0 0)", "rgb(101% 0% 0%)",
  "rgba(0,0,0,2)", "rgb(0 0 0 / -1%)", "rgb(0 0 0 / 101%)",
  "rgb(1, 2 3)", "rgb(1,2,3 / .5)", "rgb(1,2,3,)", "rgb(1 2 3 /)",
  "rgb(1 2 3 / .5 / .5)", "rgb(1, 2%, 3)",
  "hsl(0 1 50%)", "hsl(0 101% 50%)", "hsl(0 50% -1%)",
  "hsl(10% 50% 50%)", "rgb(NaN 0 0)", "rgb(1e309 0 0)",
  "hsl(1e309deg 50% 50%)", "rgb(0x10 0 0)",
]) {
  assert.equal(history.detectColor(invalid), "", invalid);
  assert.equal(history.colorDetails(invalid), null, invalid);
}

const colorExpression = " \tRgBa(100%, 0%, 0%, 50%)\n";
const colorHistory = parsedEntries([
  "ordinary text",
  colorExpression,
  { type: "text", text: "not a color", color: "#FF0000" },
]);
const colorRows = history.displayRows(colorHistory, "", 50, "colors");
assert.deepEqual(colorRows.map((row) => row.index), [1]);
assert.equal(colorRows[0].colorDetails.alpha, 0.5);
assert.equal(history.entryText(colorHistory, colorRows[0].index), colorExpression);
const savedColors = JSON.parse(history.serializeHistory(colorHistory).text);
assert.deepEqual(savedColors[1], { type: "text", text: colorExpression });
assert.deepEqual(
  history.displayRows(history.parseHistory(JSON.stringify(savedColors)).entries, "", 50, "colors")
    .map((row) => row.index),
  [1],
);

const entries = parsedEntries([
  { type: "text", text: "#a954f4" },
  { type: "text", text: "ordinary text" },
  { type: "image", path: "/tmp/example.png", mime: "image/png" },
  { type: "text", text: "file:///tmp/file.txt" },
]);

assert.deepEqual(
  history.displayRows(entries, "", 50, "colors").map((row) => row.entryType),
  ["color"],
);
assert.equal(history.displayRows(entries, "", 50, "colors")[0].index, 0);
assert.deepEqual(
  history.displayRows(entries, "", 50, "images").map((row) => row.entryType),
  ["image"],
);
assert.equal(history.displayRows(entries, "", 50, "images")[0].index, 2);
assert.deepEqual(
  history.displayRows(entries, "ordinary", 50, "all").map((row) => row.previewText),
  ["ordinary text"],
);
assert.equal(history.displayRows(entries, "ordinary", 50, "all")[0].index, 1);
assert.equal(history.displayRows(entries, "", 50, "text").length, 2);

assert.equal(history.findTextIndex(entries, "#a954f4"), 0);
assert.equal(history.findTextIndex(entries, "ordinary text"), 1);
assert.equal(history.findTextIndex(entries, "missing"), -1);

const externallyShifted = history.addEntry(
  entries,
  { type: "text", text: "new capture" },
  50,
);
assert.equal(externallyShifted.status, "ok");
assert.equal(history.findTextIndex(externallyShifted.entries, "ordinary text"), 2);

const promoted = history.addEntry(
  externallyShifted.entries,
  { type: "text", text: "ordinary text" },
  50,
);
assert.equal(promoted.status, "ok");
assert.equal(history.findTextIndex(promoted.entries, "ordinary text"), 0);
assert.notEqual(
  history.serializeHistory(promoted.entries, 50, 1).text,
  history.serializeHistory(externallyShifted.entries, 50, 1).text,
);

const invalidAdded = history.addEntry(entries, { type: "text", text: " \n\t" }, 50);
assert.equal(invalidAdded.status, "invalid");
assert.deepEqual(invalidAdded.entries, entries);

const longText = "x".repeat(140000);
const longEntries = parsedEntries([{ type: "text", text: longText }]);
const preview = history.textPreview(longEntries, 0, 65536);
assert.equal(preview.text.length, 65536);
assert.equal(preview.totalLength, 140000);
assert.equal(preview.truncated, true);
assert.equal(history.entryText(longEntries, 0).length, 140000);

const removed = history.removeEntryAt(entries, 1);
assert.deepEqual(
  removed.map((entry) => entry.type === "text" ? entry.text : entry.path),
  ["#a954f4", "/tmp/example.png", "file:///tmp/file.txt"],
);
assert.deepEqual(history.removeEntryAt(entries, 99), entries);

const serialized = history.serializeHistory(entries, 50, 1);
assert.equal(serialized.status, "ok");
const stored = JSON.parse(serialized.text);
assert.deepEqual(stored[0], { type: "text", text: "#a954f4" });
assert.deepEqual(stored[2], {
  type: "image",
  path: "/tmp/example.png",
  mime: "image/png",
});
assert.equal(
  history.historiesEqual(entries, history.parseHistory(serialized.text).entries),
  true,
);
assert.equal(history.historiesEqual(entries, removed), false);
const matchingWrite = history.parseHistory(serialized.text);
assert.equal(
  history.historyWriteDisposition(matchingWrite, entries, false, false),
  "pending",
);
assert.equal(
  history.historyWriteDisposition(matchingWrite, entries, true, false),
  "confirmed",
);
assert.equal(
  history.historyWriteDisposition(matchingWrite, removed, true, false),
  "failed",
);
assert.equal(
  history.historyWriteDisposition(matchingWrite, entries, false, true),
  "failed",
);

const edited = history.addEntry(
  entries,
  { type: "text", text: "--copy-only" },
  50,
);
assert.equal(edited.status, "ok");
assert.equal(edited.entries[0].text, "--copy-only");
assert.equal(edited.entries.length, entries.length + 1);
assert.equal(
  history.addEntry(edited.entries, { type: "text", text: "--copy-only" }, 50).entries.length,
  edited.entries.length,
);

const editedLarge = history.addEntry(
  entries,
  { type: "text", text: longText + "X" },
  50,
);
assert.equal(editedLarge.status, "ok");
const storedLarge = history.serializeHistory(editedLarge.entries, 50, 1);
assert.equal(storedLarge.status, "ok");
assert.equal(JSON.parse(storedLarge.text)[0].text.length, 140001);
assert.equal(history.parseHistory(storedLarge.text).entries[0].text, longText + "X");

const oneNewline = history.serializeHistory(entries, 50, 1);
const twoNewlines = history.serializeHistory(entries, 50, 2);
assert.equal(oneNewline.text.endsWith("\n\n"), false);
assert.equal(twoNewlines.text.endsWith("\n\n"), true);
assert.notEqual(oneNewline.text, twoNewlines.text);
assert.deepEqual(JSON.parse(oneNewline.text), JSON.parse(twoNewlines.text));

const exactRawLimit = " ".repeat(history.maxHistoryFileBytes);
assert.equal(history.parseHistory(exactRawLimit).status, "invalid");
assert.equal(history.parseHistory(exactRawLimit + " ").status, "oversized");
assert.equal(
  history.parseHistory("é".repeat(history.maxHistoryFileBytes / 2 + 1)).status,
  "oversized",
);

const exactEntryText = "e".repeat(history.maxEntryTextLength);
assert.equal(
  history.parseHistory(JSON.stringify([{ type: "text", text: exactEntryText }])).status,
  "ok",
);
const overLimitText = "e".repeat(history.maxEntryTextLength + 1);
const oversizedStock = history.parseHistory(JSON.stringify([
  { type: "text", text: "before oversized" },
  { type: "text", text: overLimitText },
  { type: "text", text: "after oversized" },
]));
assert.equal(oversizedStock.status, "ok");
assert.equal(oversizedStock.containsOversized, true);
assert.equal(oversizedStock.entries.length, 3);
assert.deepEqual(oversizedStock.entries[1], {
  type: "text",
  text: "",
  oversized: true,
  originalLength: history.maxEntryTextLength + 1,
});
assert.deepEqual(
  history.displayRows(oversizedStock.entries, "", 50, "all").map((row) => row.entryType),
  ["text", "oversized", "text"],
);
assert.equal(
  history.displayRows(oversizedStock.entries, "after", 50, "all")[0].index,
  2,
);
assert.equal(history.displayRows(oversizedStock.entries, "1048577", 50, "all").length, 0);
assert.equal(history.entryText(oversizedStock.entries, 1), "");
assert.equal(history.serializeHistory(oversizedStock.entries, 50, 1).status, "oversized");
assert.equal(history.serializeHistory(oversizedStock.entries, 50, 1).containsOversized, true);
assert.equal(history.validateHistory(oversizedStock.entries).status, "ok");
assert.equal(
  history.parseHistory(JSON.stringify([{
    type: "text",
    text: "x",
    oversized: true,
    originalLength: history.maxEntryTextLength + 1,
  }])).status,
  "invalid",
);

const addWithOversized = history.addEntry(
  oversizedStock.entries,
  { type: "text", text: "must not discard history" },
  50,
);
assert.equal(addWithOversized.status, "oversized");
assert.equal(addWithOversized.containsOversized, true);
assert.deepEqual(addWithOversized.entries, oversizedStock.entries);

const withoutOversized = history.removeEntryAt(oversizedStock.entries, 1);
assert.equal(history.serializeHistory(withoutOversized, 50, 1).status, "ok");
assert.deepEqual(
  JSON.parse(history.serializeHistory(withoutOversized, 50, 1).text)
    .map((entry) => entry.text),
  ["before oversized", "after oversized"],
);

const twoOversized = history.parseHistory(JSON.stringify([
  { type: "text", text: overLimitText },
  { type: "text", text: overLimitText },
]));
assert.equal(twoOversized.status, "ok");
assert.equal(twoOversized.entries.length, 2);
assert.equal(
  history.serializeHistory(history.removeEntryAt(twoOversized.entries, 0), 50, 1).status,
  "oversized",
);

assert.equal(
  history.addEntry([], "e".repeat(history.maxEntryTextLength + 1), 50).status,
  "oversized",
);

const counted = history.parseHistory(JSON.stringify(
  Array.from(
    { length: history.maxHistoryEntries + 1 },
    (_, index) => ({ type: "text", text: `entry-${index}` }),
  ),
));
assert.equal(counted.status, "ok");
assert.equal(counted.truncated, true);
assert.equal(counted.entries.length, history.maxHistoryEntries);
assert.equal(
  history.displayRows(counted.entries, "entry-299", 50, "all")[0].index,
  299,
);

const invalidMiddle = history.parseHistory(JSON.stringify([
  { type: "text", text: "first" },
  null,
  { type: "text", text: "third" },
]));
assert.equal(invalidMiddle.status, "invalid");
assert.deepEqual(invalidMiddle.entries, []);

assert.equal(
  history.parseHistory(JSON.stringify([
    { type: "image", path: "relative.png", mime: "image/png" },
  ])).status,
  "invalid",
);
assert.equal(
  history.parseHistory(JSON.stringify([
    { type: "image", path: "/tmp/example.png", mime: "text/html" },
  ])).status,
  "invalid",
);
assert.equal(
  history.parseHistory(JSON.stringify([
    {
      type: "image",
      path: "/" + "p".repeat(history.maxImagePathLength),
      mime: "image/png",
    },
  ])).status,
  "invalid",
);
assert.equal(
  history.parseHistory(JSON.stringify([
    {
      type: "image",
      path: "/tmp/example.png",
      mime: "image/png",
      capturedAt: "t".repeat(history.maxCapturedAtLength + 1),
    },
  ])).status,
  "invalid",
);

const maximumChunks = Array.from(
  { length: 4 },
  (_, index) => ({
    type: "text",
    text: "q".repeat(history.maxEntryTextLength - 1) + String(index),
  }),
);
assert.equal(history.validateHistory(maximumChunks).status, "ok");
assert.equal(
  history.validateHistory(maximumChunks.concat(maximumChunks[0])).status,
  "oversized",
);
assert.equal(history.serializeHistory(maximumChunks, 300, 1).status, "oversized");

const aggregateRejected = history.addEntry(
  maximumChunks,
  { type: "text", text: "new" },
  300,
);
assert.equal(aggregateRejected.status, "oversized");
assert.equal(aggregateRejected.truncated, false);
assert.deepEqual(
  aggregateRejected.entries.map((entry) => entry.text),
  maximumChunks.map((entry) => entry.text),
);

const countTrimmed = history.addEntry(
  counted.entries,
  { type: "text", text: "newest" },
  history.maxHistoryEntries,
);
assert.equal(countTrimmed.status, "ok");
assert.equal(countTrimmed.truncated, true);
assert.equal(countTrimmed.entries.length, history.maxHistoryEntries);
assert.equal(countTrimmed.entries[0].text, "newest");

console.log("clipboard history model: ok");
