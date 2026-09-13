#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
let root = process.cwd();

// Parse --root argument
for (let i = 0; i < args.length; i++) {
	if (args[i] === '--root' && i + 1 < args.length) {
		root = args[i + 1];
		break;
	}
}

const guideDir = path.join(root, 'docs', 'systems');
const tuningFile = path.join(root, 'scripts', 'sim', 'tuning.gd');

const requiredFiles = [
	'README.md',
	'01-battle.md',
	'02-overworld.md',
	'03-plinko-towns.md',
	'04-meta-progression.md',
	'05-presentation-save.md',
	'06-tuning-reference.md'
];

const fileOrder = ['README.md', '01-battle.md', '02-overworld.md', '03-plinko-towns.md', '04-meta-progression.md', '05-presentation-save.md', '06-tuning-reference.md'];
const numberedFiles = ['01-battle.md', '02-overworld.md', '03-plinko-towns.md', '04-meta-progression.md', '05-presentation-save.md'];

const errors = [];

// Helper: normalize line endings
function normalize(text) {
	return text.replace(/\r\n/g, '\n');
}

// Helper: read file safely
function readFile(filePath) {
	try {
		return normalize(fs.readFileSync(filePath, 'utf-8'));
	} catch (e) {
		return null;
	}
}

// Helper: check if file exists
function fileExists(filePath) {
	try {
		fs.accessSync(filePath);
		return true;
	} catch (e) {
		return false;
	}
}

// R1: Parse tuning constants
const tuningContent = readFile(tuningFile);
const tuningConsts = new Map(); // name -> value

if (tuningContent) {
	const constRegex = /^const\s+([A-Z][A-Z0-9_]*)\s*(?::=|:\s*[A-Za-z0-9_\[\]]+\s*=|=)\s*(.+?)\s*$/gm;
	let match;
	while ((match = constRegex.exec(tuningContent)) !== null) {
		let value = match[2];
		// Strip trailing comment if value contains no quotes and matches trailing comment pattern
		if (!value.includes('"') && /\s+#.*$/.test(value)) {
			value = value.replace(/\s+#.*$/, '').trim();
		}
		tuningConsts.set(match[1], value);
	}
}

const constCount = tuningConsts.size;

// R2: Check required files
const missingFiles = [];
const existingFiles = new Set();

for (const file of requiredFiles) {
	const filePath = path.join(guideDir, file);
	if (!fileExists(filePath)) {
		errors.push(`MISSING_FILE ${file}`);
		missingFiles.push(file);
	} else {
		existingFiles.add(file);
	}
}

// Process files in order
let rowCount = 0;
const guideFiles = [];
for (const file of fileOrder) {
	if (existingFiles.has(file)) {
		guideFiles.push(file);
	}
}

// Track knobs per file and in 06
const knobsPerFile = new Map();
const knobs06 = new Map(); // for tracking UNCOVERED
const seen06 = new Set(); // for tracking DUPLICATE

for (const fileName of guideFiles) {
	const filePath = path.join(guideDir, fileName);
	const content = readFile(filePath);
	if (!content) continue;

	const lines = content.split('\n');
	const knobsThisFile = [];

	// R3: Check headings (for files 01-05)
	if (numberedFiles.includes(fileName)) {
		const headingRegex = /^## (.*)$/;
		const headings = [];
		const fencedLines = new Set();

		// Mark fenced lines
		let inFence = false;
		for (let i = 0; i < lines.length; i++) {
			if (lines[i].startsWith('```')) {
				fencedLines.add(i);
				inFence = !inFence;
			} else if (inFence) {
				fencedLines.add(i);
			}
		}

		for (let i = 0; i < lines.length; i++) {
			if (!fencedLines.has(i)) {
				const match = headingRegex.exec(lines[i]);
				if (match) {
					headings.push(`## ${match[1]}`);
				}
			}
		}

		const expectedHeadings = [
			'## What it does',
			'## Where it lives',
			'## How it works',
			'## Knobs',
			'## Tweak recipes',
			'## Gotchas'
		];

		if (JSON.stringify(headings) !== JSON.stringify(expectedHeadings)) {
			errors.push(`HEADINGS ${fileName}`);
		}
	}

	// Mark fenced lines for other rules
	const fencedLines = new Set();
	{
		let inFence = false;
		for (let i = 0; i < lines.length; i++) {
			if (lines[i].startsWith('```')) {
				fencedLines.add(i);
				inFence = !inFence;
			} else if (inFence) {
				fencedLines.add(i);
			}
		}
	}

	// R4: Check knob rows
	const knobRowRegex = /^\|\s*`([A-Z][A-Z0-9_]*)`\s*\|\s*`([^`]*)`\s*\|/;
	for (let i = 0; i < lines.length; i++) {
		if (!fencedLines.has(i)) {
			const match = knobRowRegex.exec(lines[i]);
			if (match) {
				const name = match[1];
				const docValue = match[2];
				const lineNum = i + 1;

				rowCount++;
				knobsThisFile.push(name);
				if (fileName === '06-tuning-reference.md') {
					if (seen06.has(name)) {
						errors.push(`DUPLICATE ${name}`);
					}
					seen06.add(name);
					knobs06.set(name, lineNum);
				}

				// Check if const exists in tuning
				if (!tuningConsts.has(name)) {
					errors.push(`UNKNOWN_CONST ${fileName}:${lineNum} ${name}`);
				} else {
					// Compare values (whitespace removed)
					const codeValue = tuningConsts.get(name);
					const docNorm = docValue.replace(/\s+/g, '');
					const codeNorm = codeValue.replace(/\s+/g, '');
					if (docNorm !== codeNorm) {
						errors.push(`VALUE_MISMATCH ${fileName}:${lineNum} ${name} doc=${docValue} code=${codeValue}`);
					}
				}
			}
		}
	}

	// R6: Check paths in inline code spans
	const pathRegex = /`([^`\n]+)`/g;
	for (let i = 0; i < lines.length; i++) {
		if (!fencedLines.has(i)) {
			const line = lines[i];
			let match;
			while ((match = pathRegex.exec(line)) !== null) {
				const content = match[1];
				// Only consider if no whitespace and starts with one of the prefixes
				if (!/\s/.test(content) && /^(scripts\/|docs\/|tools\/|scenes\/|shaders\/)/.test(content)) {
					const parts = content.split('::');
					const filePath = parts[0];
					const func = parts[1];
					const fullPath = path.join(root, filePath);

					// Check if file exists
					if (!fileExists(fullPath)) {
						errors.push(`BAD_PATH ${fileName}:${i + 1} ${filePath}`);
					} else if (func) {
						// Check if function exists
						const fileContent = readFile(fullPath);
						if (fileContent) {
							const funcRegex = new RegExp(`^\\s*(static\\s+)?func\\s+${func}\\s*\\(`, 'm');
							if (!funcRegex.test(fileContent)) {
								errors.push(`BAD_FUNC ${fileName}:${i + 1} ${content}`);
							}
						}
					}
				}
			}
		}
	}

	// R7: Check links
	const linkRegex = /\]\(([^)\s]+)\)/g;
	for (let i = 0; i < lines.length; i++) {
		if (!fencedLines.has(i)) {
			const line = lines[i];
			let match;
			while ((match = linkRegex.exec(line)) !== null) {
				let target = match[1];
				// Skip special targets
				if (target.startsWith('http:') || target.startsWith('https:') || target.startsWith('mailto:') || target.startsWith('#')) {
					continue;
				}
				// Strip #... suffix
				target = target.split('#')[0];

				// Resolve relative to guide file's directory
				const resolvedPath = path.join(guideDir, target);
				if (!fileExists(resolvedPath)) {
					errors.push(`BAD_LINK ${fileName}:${i + 1} ${target}`);
				}
			}
		}
	}

	// R8: Check for UNDECIDED lines
	for (let i = 0; i < lines.length; i++) {
		if (lines[i].includes('// UNDECIDED:')) {
			errors.push(`UNDECIDED ${fileName}:${i + 1}`);
		}
	}

	knobsPerFile.set(fileName, knobsThisFile);
}

// R5: Check coverage in 06-tuning-reference.md (if present)
if (existingFiles.has('06-tuning-reference.md')) {
	// Check for UNCOVERED
	const tuningOrder = [];
	const tuningContent = readFile(tuningFile);
	if (tuningContent) {
		const constRegex = /^const\s+([A-Z][A-Z0-9_]*)\s*(?::=|:\s*[A-Za-z0-9_\[\]]+\s*=|=)\s*(.+?)\s*$/gm;
		let match;
		while ((match = constRegex.exec(tuningContent)) !== null) {
			tuningOrder.push(match[1]);
		}
	}

	for (const name of tuningOrder) {
		if (!knobs06.has(name)) {
			errors.push(`UNCOVERED ${name}`);
		}
	}
}

// Output errors in order: R2, then per file: R3, R4, R6, R7, R8, then R5
// Categorize errors
const r2Errors = [];
const r5Errors = [];
const perFileErrors = new Map(); // file -> { r3: [], r4: [], r6: [], r7: [], r8: [] }

for (const error of errors) {
	const match = error.match(/^([A-Z_]+)/);
	if (!match) continue;

	const type = match[1];

	if (type === 'MISSING_FILE') {
		r2Errors.push(error);
	} else if (type === 'DUPLICATE' || type === 'UNCOVERED') {
		r5Errors.push(error);
	} else {
		// Determine rule type and file
		let ruleType, file, line;

		if (type === 'HEADINGS') {
			ruleType = 'r3';
			const fileMatch = error.match(/HEADINGS\s+(\S+)/);
			file = fileMatch ? fileMatch[1] : null;
			line = Infinity; // r3 has no line, sort first
		} else if (type === 'VALUE_MISMATCH' || type === 'UNKNOWN_CONST') {
			ruleType = 'r4';
			const fileMatch = error.match(/[A-Z_]+\s+([^:]+):(\d+)/);
			if (fileMatch) {
				file = fileMatch[1];
				line = parseInt(fileMatch[2]);
			}
		} else if (type === 'BAD_PATH' || type === 'BAD_FUNC') {
			ruleType = 'r6';
			const fileMatch = error.match(/[A-Z_]+\s+([^:]+):(\d+)/);
			if (fileMatch) {
				file = fileMatch[1];
				line = parseInt(fileMatch[2]);
			}
		} else if (type === 'BAD_LINK') {
			ruleType = 'r7';
			const fileMatch = error.match(/[A-Z_]+\s+([^:]+):(\d+)/);
			if (fileMatch) {
				file = fileMatch[1];
				line = parseInt(fileMatch[2]);
			}
		} else if (type === 'UNDECIDED') {
			ruleType = 'r8';
			const fileMatch = error.match(/UNDECIDED\s+([^:]+):(\d+)/);
			if (fileMatch) {
				file = fileMatch[1];
				line = parseInt(fileMatch[2]);
			}
		}

		if (file && ruleType) {
			if (!perFileErrors.has(file)) {
				perFileErrors.set(file, { r3: [], r4: [], r6: [], r7: [], r8: [] });
			}
			const ruleOrder = { r3: 1, r4: 2, r6: 3, r7: 4, r8: 5 };
			perFileErrors.get(file)[ruleType].push({ error, line, ruleOrder: ruleOrder[ruleType] });
		}
	}
}

// Build final error list
const finalErrors = [];

// Add R2 errors
finalErrors.push(...r2Errors);

// Add per-file errors in file order
for (const file of fileOrder) {
	if (perFileErrors.has(file)) {
		const fileErrors = perFileErrors.get(file);
		const allRules = ['r3', 'r4', 'r6', 'r7', 'r8'];

		for (const rule of allRules) {
			// Sort by line number
			fileErrors[rule].sort((a, b) => a.line - b.line);
			for (const entry of fileErrors[rule]) {
				finalErrors.push(entry.error);
			}
		}
	}
}

// Add R5 errors
finalErrors.push(...r5Errors);

// Output
for (const error of finalErrors) {
	console.log(error);
}

if (finalErrors.length === 0) {
	console.log(`GUIDE_OK consts=${constCount} rows=${rowCount}`);
	process.exit(0);
} else {
	console.log(`GUIDE_FAIL errors=${finalErrors.length}`);
	process.exit(1);
}
