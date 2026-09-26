"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const { replaceInDirectory, replaceInFile, replaceInPath, runCli } = require("../replace-text");

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "replace-text-test-"));
}

test("replaces tokens case-insensitively and leaves partial-word matches intact", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  const filePath = path.join(dir, "notes.jsonl");
  const original = "Foo foo FOO fOo\nFoo: [foo] {FOO}\nFool preFoo foo1 _foo 1foo foo_";
  fs.writeFileSync(filePath, original, "utf8");

  const summary = replaceInDirectory({ dir, from: "Foo", to: "Bar" });
  const next = fs.readFileSync(filePath, "utf8");

  assert.equal(next, "Bar bar BAR bAr\nBar: [bar] {BAR}\nFool preFoo foo1 _foo 1foo foo_");
  assert.equal(summary.replacements, 7);
  assert.equal(summary.changedFiles, 1);
  assert.ok(fs.existsSync(summary.backupDir));
  assert.equal(fs.readFileSync(path.join(summary.backupDir, "notes.jsonl"), "utf8"), original);
});

test("treats escaped control sequences in json strings as token boundaries", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  const filePath = path.join(dir, "records.jsonl");
  const original = "{\"text\":\"intro\\n\\nFoo: first line\\nfoo: second line\\nFood is unchanged\"}";
  fs.writeFileSync(filePath, original, "utf8");

  const summary = replaceInDirectory({ dir, from: "Foo", to: "Bar" });
  const next = fs.readFileSync(filePath, "utf8");

  assert.equal(next, "{\"text\":\"intro\\n\\nBar: first line\\nbar: second line\\nFood is unchanged\"}");
  assert.equal(summary.replacements, 2);
  assert.equal(summary.changedFiles, 1);
});

test("recurses into directories and skips binary files", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  const nestedDir = path.join(dir, "nested");
  fs.mkdirSync(nestedDir);

  const rootText = path.join(dir, "root.jsonl");
  const nestedText = path.join(nestedDir, "nested.jsonl");
  const binaryFile = path.join(nestedDir, "asset.bin");

  fs.writeFileSync(rootText, "foo says hi.\nFOO:", "utf8");
  fs.writeFileSync(nestedText, "Start FoO End", "utf8");
  fs.writeFileSync(binaryFile, Buffer.from([0, 1, 2, 70, 111, 111, 255]));

  const binaryBefore = fs.readFileSync(binaryFile);
  const summary = replaceInDirectory({ dir, from: "Foo", to: "Bar" });
  const binaryAfter = fs.readFileSync(binaryFile);

  assert.equal(fs.readFileSync(rootText, "utf8"), "bar says hi.\nBAR:");
  assert.equal(fs.readFileSync(nestedText, "utf8"), "Start BaR End");
  assert.deepEqual(binaryAfter, binaryBefore);
  assert.equal(summary.changedFiles, 2);
  assert.equal(summary.replacements, 3);
  assert.equal(summary.skippedBinaryFiles, 1);
  assert.equal(fs.readFileSync(path.join(summary.backupDir, "nested", "nested.jsonl"), "utf8"), "Start FoO End");
});

test("replaces tokens in a single file without scanning sibling files", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  const filePath = path.join(dir, "only-this.jsonl");
  const siblingPath = path.join(dir, "leave-this.jsonl");
  const original = "Foo foo FOO Fool";
  fs.writeFileSync(filePath, original, "utf8");
  fs.writeFileSync(siblingPath, "Foo stays here", "utf8");

  const summary = replaceInFile({ file: filePath, from: "Foo", to: "Bar" });

  assert.equal(fs.readFileSync(filePath, "utf8"), "Bar bar BAR Fool");
  assert.equal(fs.readFileSync(siblingPath, "utf8"), "Foo stays here");
  assert.equal(summary.scannedFiles, 1);
  assert.equal(summary.textFiles, 1);
  assert.equal(summary.changedFiles, 1);
  assert.equal(summary.replacements, 3);
  assert.ok(fs.existsSync(summary.backupFile));
  assert.equal(fs.readFileSync(summary.backupFile, "utf8"), original);
});

test("dispatches path replacement to file or directory mode", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  const filePath = path.join(dir, "single.txt");
  fs.writeFileSync(filePath, "Foo", "utf8");

  const fileSummary = replaceInPath({ target: filePath, from: "Foo", to: "Bar" });
  assert.equal(fs.readFileSync(filePath, "utf8"), "Bar");
  assert.equal(fileSummary.scannedFiles, 1);
  assert.ok(fileSummary.backupFile);

  const nestedPath = path.join(dir, "nested.txt");
  fs.writeFileSync(nestedPath, "Foo", "utf8");

  const dirSummary = replaceInPath({ target: dir, from: "Foo", to: "Baz" });
  assert.equal(fs.readFileSync(nestedPath, "utf8"), "Baz");
  assert.ok(dirSummary.scannedFiles >= 2);
  assert.ok(dirSummary.backupDir);
});

test("cli accepts a file path as the replacement target", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  const filePath = path.join(dir, "cli.txt");
  fs.writeFileSync(filePath, "Foo", "utf8");

  assert.equal(runCli([filePath, "Foo", "Bar"]), 0);
  assert.equal(fs.readFileSync(filePath, "utf8"), "Bar");
});

test("throws when from value is empty", (t) => {
  const dir = makeTempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  fs.writeFileSync(path.join(dir, "x.txt"), "Foo", "utf8");
  assert.throws(
    () => replaceInDirectory({ dir, from: "", to: "Bar" }),
    /`from` must be a non-empty string/
  );
});
