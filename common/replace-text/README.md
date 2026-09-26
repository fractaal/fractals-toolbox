# String Replacement CLI

Replaces an exact token in one text file or recursively across a directory, skips binary files, and creates an automatic backup of the target file or directory before any modification.

## Usage

```bash
replace-text <file-or-directory> <from> <to>
```

Example:

```bash
replace-text ./data Foo Bar
replace-text ./data/notes.jsonl Foo Bar
```

Matching is case-insensitive and output casing follows the matched token style:

- `Foo -> Bar`
- `foo -> bar`
- `FOO -> BAR`

It still only replaces standalone tokens (`Foo`, `Foo:`, `\nFoo`, etc.) while avoiding partial-word changes like `Fool`.
Escaped control sequences in JSON/JSONL (for example `\\nFoo:` inside a JSON string) are handled as token boundaries too, so they become `\\nBar:`.

## Run tests

```bash
node --test common/replace-text/test/replace-text.test.js
```
