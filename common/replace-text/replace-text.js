#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isLetterChar(char) {
  return /\p{L}/u.test(char);
}

function detectCharCase(char) {
  if (!isLetterChar(char)) {
    return null;
  }

  if (char === char.toUpperCase() && char !== char.toLowerCase()) {
    return "upper";
  }
  if (char === char.toLowerCase() && char !== char.toUpperCase()) {
    return "lower";
  }

  return null;
}

function capitalizeLikeTitleCase(value) {
  let didCapitalize = false;
  return Array.from(value)
    .map((char) => {
      if (!isLetterChar(char)) {
        return char;
      }
      if (!didCapitalize) {
        didCapitalize = true;
        return char.toUpperCase();
      }
      return char.toLowerCase();
    })
    .join("");
}

function applyCharacterCasePattern(reference, replacement) {
  const referenceChars = Array.from(reference);
  const replacementChars = Array.from(replacement);
  let fallbackCase = "lower";

  const transformed = replacementChars.map((char, index) => {
    if (!isLetterChar(char)) {
      return char;
    }

    const refIndex = Math.min(index, referenceChars.length - 1);
    const refCase = detectCharCase(referenceChars[refIndex]);
    const caseToUse = refCase || fallbackCase;
    fallbackCase = caseToUse;
    return caseToUse === "upper" ? char.toUpperCase() : char.toLowerCase();
  });

  return transformed.join("");
}

function adaptReplacementCase(matchedText, replacementText) {
  if (!/\p{L}/u.test(matchedText) || !/\p{L}/u.test(replacementText)) {
    return replacementText;
  }

  if (matchedText === matchedText.toUpperCase()) {
    return replacementText.toUpperCase();
  }
  if (matchedText === matchedText.toLowerCase()) {
    return replacementText.toLowerCase();
  }

  const titleCaseReference = capitalizeLikeTitleCase(matchedText.toLowerCase());
  if (matchedText === titleCaseReference) {
    return capitalizeLikeTitleCase(replacementText);
  }

  return applyCharacterCasePattern(matchedText, replacementText);
}

function isWordChar(char) {
  return /[\p{L}\p{N}_]/u.test(char);
}

function isHexChar(char) {
  return /^[0-9A-Fa-f]$/.test(char);
}

function isEscapedControlBoundaryBefore(text, index) {
  if (index >= 2) {
    const prefixTwoChars = text.slice(index - 2, index);
    if (/^\\[\\/"'bfnrtv0]$/u.test(prefixTwoChars)) {
      return true;
    }
  }

  if (
    index >= 4 &&
    text[index - 4] === "\\" &&
    (text[index - 3] === "x" || text[index - 3] === "X") &&
    isHexChar(text[index - 2]) &&
    isHexChar(text[index - 1])
  ) {
    return true;
  }

  if (
    index >= 6 &&
    text[index - 6] === "\\" &&
    (text[index - 5] === "u" || text[index - 5] === "U") &&
    isHexChar(text[index - 4]) &&
    isHexChar(text[index - 3]) &&
    isHexChar(text[index - 2]) &&
    isHexChar(text[index - 1])
  ) {
    return true;
  }

  return false;
}

function hasTokenBoundaryBefore(text, startIndex) {
  if (startIndex === 0) {
    return true;
  }

  const prevChar = text[startIndex - 1];
  if (!isWordChar(prevChar)) {
    return true;
  }

  return isEscapedControlBoundaryBefore(text, startIndex);
}

function hasTokenBoundaryAfter(text, endIndex) {
  if (endIndex >= text.length) {
    return true;
  }

  return !isWordChar(text[endIndex]);
}

function isStandaloneTokenMatch(text, startIndex, matchLength) {
  const endIndex = startIndex + matchLength;
  return hasTokenBoundaryBefore(text, startIndex) && hasTokenBoundaryAfter(text, endIndex);
}

function formatTimestamp(date = new Date()) {
  const pad2 = (n) => String(n).padStart(2, "0");
  const pad3 = (n) => String(n).padStart(3, "0");
  return `${date.getFullYear()}${pad2(date.getMonth() + 1)}${pad2(date.getDate())}-${pad2(date.getHours())}${pad2(date.getMinutes())}${pad2(date.getSeconds())}${pad3(date.getMilliseconds())}`;
}

function isProbablyBinary(buffer) {
  if (buffer.includes(0)) {
    return true;
  }

  const sampleSize = Math.min(buffer.length, 8000);
  if (sampleSize === 0) {
    return false;
  }

  let suspicious = 0;
  for (let i = 0; i < sampleSize; i += 1) {
    const byte = buffer[i];
    const isControlByte = byte < 7 || (byte > 13 && byte < 32);
    if (isControlByte) {
      suspicious += 1;
    }
  }

  return suspicious / sampleSize > 0.3;
}

function collectFiles(dirPath, output = []) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      collectFiles(fullPath, output);
      continue;
    }

    if (entry.isFile()) {
      output.push(fullPath);
    }
  }
  return output;
}

function copyBackup(sourcePath) {
  const absoluteSourcePath = path.resolve(sourcePath);
  const backupPath = `${absoluteSourcePath}.backup-${formatTimestamp()}`;
  fs.cpSync(absoluteSourcePath, backupPath, {
    recursive: true,
    errorOnExist: true,
    force: false,
    preserveTimestamps: true
  });
  return backupPath;
}

function createBackupDirectory(sourceDir) {
  return copyBackup(sourceDir);
}

function createBackupFile(sourceFile) {
  return copyBackup(sourceFile);
}

function buildTokenRegex(from) {
  if (typeof from !== "string" || from.length === 0) {
    throw new Error("`from` must be a non-empty string.");
  }

  return new RegExp(escapeRegExp(from), "giu");
}

function replaceInTextFile(filePath, regex, to) {
  const buffer = fs.readFileSync(filePath);
  if (isProbablyBinary(buffer)) {
    return { textFile: false, changed: false, replacements: 0, skippedBinary: true };
  }

  const originalText = buffer.toString("utf8");
  let replacements = 0;
  regex.lastIndex = 0;
  const nextText = originalText.replace(regex, (matchedText, offset, sourceText) => {
    if (!isStandaloneTokenMatch(sourceText, offset, matchedText.length)) {
      return matchedText;
    }
    replacements += 1;
    return adaptReplacementCase(matchedText, to);
  });

  if (replacements === 0) {
    return { textFile: true, changed: false, replacements: 0, skippedBinary: false };
  }

  fs.writeFileSync(filePath, nextText, "utf8");
  return { textFile: true, changed: true, replacements, skippedBinary: false };
}

function makeEmptySummary(backupPath) {
  return {
    backupPath,
    scannedFiles: 0,
    textFiles: 0,
    changedFiles: 0,
    replacements: 0,
    skippedBinaryFiles: 0
  };
}

function addFileResultToSummary(summary, fileResult) {
  summary.scannedFiles += 1;
  if (fileResult.skippedBinary) {
    summary.skippedBinaryFiles += 1;
    return;
  }

  summary.textFiles += 1;
  if (!fileResult.changed) {
    return;
  }

  summary.changedFiles += 1;
  summary.replacements += fileResult.replacements;
}

function replaceInDirectory(options) {
  const { dir, from, to } = options;

  if (typeof dir !== "string" || dir.trim() === "") {
    throw new Error("`dir` must be a non-empty string.");
  }
  if (typeof from !== "string" || from.length === 0) {
    throw new Error("`from` must be a non-empty string.");
  }
  if (typeof to !== "string") {
    throw new Error("`to` must be a string.");
  }

  const absoluteDir = path.resolve(dir);
  const directoryStats = fs.statSync(absoluteDir, { throwIfNoEntry: true });
  if (!directoryStats.isDirectory()) {
    throw new Error("`dir` must point to a directory.");
  }

  const regex = buildTokenRegex(from);
  const backupDir = createBackupDirectory(absoluteDir);
  const allFiles = collectFiles(absoluteDir);
  const summary = makeEmptySummary(backupDir);
  summary.backupDir = backupDir;

  for (const filePath of allFiles) {
    addFileResultToSummary(summary, replaceInTextFile(filePath, regex, to));
  }

  return summary;
}

function replaceInFile(options) {
  const { file, from, to } = options;

  if (typeof file !== "string" || file.trim() === "") {
    throw new Error("`file` must be a non-empty string.");
  }
  if (typeof from !== "string" || from.length === 0) {
    throw new Error("`from` must be a non-empty string.");
  }
  if (typeof to !== "string") {
    throw new Error("`to` must be a string.");
  }

  const absoluteFile = path.resolve(file);
  const fileStats = fs.statSync(absoluteFile, { throwIfNoEntry: true });
  if (!fileStats.isFile()) {
    throw new Error("`file` must point to a file.");
  }

  const regex = buildTokenRegex(from);
  const backupFile = createBackupFile(absoluteFile);
  const summary = makeEmptySummary(backupFile);
  summary.backupFile = backupFile;
  addFileResultToSummary(summary, replaceInTextFile(absoluteFile, regex, to));
  return summary;
}

function replaceInPath(options) {
  const { target, from, to } = options;

  if (typeof target !== "string" || target.trim() === "") {
    throw new Error("`target` must be a non-empty string.");
  }

  const absoluteTarget = path.resolve(target);
  const targetStats = fs.statSync(absoluteTarget, { throwIfNoEntry: true });
  if (targetStats.isDirectory()) {
    return replaceInDirectory({ dir: absoluteTarget, from, to });
  }
  if (targetStats.isFile()) {
    return replaceInFile({ file: absoluteTarget, from, to });
  }

  throw new Error("`target` must point to a file or directory.");
}

function printUsage() {
  console.error("Usage: replace-text <file-or-directory> <from> <to>");
  console.error("");
  console.error("Examples:");
  console.error("  replace-text ./data Foo Bar");
  console.error("  replace-text ./data/notes.jsonl Foo Bar");
}

function runCli(argv = process.argv.slice(2)) {
  if (argv.length < 3) {
    printUsage();
    return 1;
  }

  const [target, from, to] = argv;
  try {
    const summary = replaceInPath({ target, from, to });
    console.log(`Backup created: ${summary.backupPath}`);
    console.log(`Scanned files: ${summary.scannedFiles}`);
    console.log(`Text files: ${summary.textFiles}`);
    console.log(`Changed files: ${summary.changedFiles}`);
    console.log(`Replacements: ${summary.replacements}`);
    console.log(`Skipped binary files: ${summary.skippedBinaryFiles}`);
    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}

if (require.main === module) {
  process.exitCode = runCli();
}

module.exports = {
  adaptReplacementCase,
  buildTokenRegex,
  collectFiles,
  createBackupDirectory,
  createBackupFile,
  isStandaloneTokenMatch,
  isProbablyBinary,
  replaceInDirectory,
  replaceInFile,
  replaceInPath,
  runCli
};
