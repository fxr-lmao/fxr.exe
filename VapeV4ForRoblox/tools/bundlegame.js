#!/usr/bin/env node
// Bundles one game folder from src/games into the single Lua chunk that
// src/main.lua expects to find at newvape/games/<PlaceId>.lua (see main.lua:94).
//
// Every module in a game folder shares one scope with its base.lua -- modules
// reach straight for base's locals (lplr, vape, applySpeed, ...) and assign to
// the forward declarations it makes (AnticheatBypass, bypassRoot, ...). So the
// bundle is a concatenation, and the only thing that has to be right is the
// order: a file must come after whatever declares the chunk-scope locals it
// reads. base.lua is pinned first, the rest are sorted from their references.
//
//   node tools/bundlegame.js "src/games/132768098780837 - blockwars"
//   node tools/bundlegame.js "src/games/..." -o /path/to/132768098780837.lua
//
// Drop the result in your executor's workspace at newvape/games/<PlaceId>.lua.
// main.lua reads that file if it exists and skips the download, so it shadows
// whatever VapeCompiled would have served. It also survives vape updates:
// NewMainScript's wipeFolder only deletes files whose first line is its cache
// watermark, and this output deliberately starts with a plain comment instead.

const fs = require('fs');
const path = require('path');

const LUA_KEYWORDS = new Set([
	'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
	'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then',
	'true', 'until', 'while', 'continue', 'self', 'export', 'type'
]);

// Luau's per-function local limit. Chunk-scope locals from every module land in
// the same function, so a big game folder can genuinely run out.
const LOCAL_LIMIT = 200;

// Blank out comments and string literals so they cannot be mistaken for code,
// preserving length and newlines so line/column positions still mean something.
function stripNonCode(src) {
	const out = src.split('');
	const blank = (from, to) => {
		for (let k = from; k < to && k < out.length; k++) {
			if (out[k] !== '\n') out[k] = ' ';
		}
	};

	let i = 0;
	while (i < src.length) {
		// Long bracket [[ ]] / [=[ ]=], as comment body or plain string
		const long = /^(--)?\[(=*)\[/.exec(src.slice(i));
		if (long) {
			const close = ']' + long[2] + ']';
			const end = src.indexOf(close, i + long[0].length);
			const stop = end === -1 ? src.length : end + close.length;
			blank(i, stop);
			i = stop;
			continue;
		}
		if (src.startsWith('--', i)) {
			let end = src.indexOf('\n', i);
			if (end === -1) end = src.length;
			blank(i, end);
			i = end;
			continue;
		}
		const ch = src[i];
		if (ch === '"' || ch === "'") {
			let j = i + 1;
			while (j < src.length && src[j] !== ch) {
				if (src[j] === '\\') j++;
				if (src[j] === '\n') break;
				j++;
			}
			blank(i, j + 1);
			i = j + 1;
			continue;
		}
		i++;
	}
	return out.join('');
}

// Locals declared at chunk scope -- column 0, so not nested in any function.
// Those are the only ones another file in the bundle can see.
function chunkScopeLocals(code) {
	const names = new Set();
	for (const line of code.split('\n')) {
		if (!line.startsWith('local ')) continue;
		const fn = /^local\s+function\s+([A-Za-z_]\w*)/.exec(line);
		if (fn) {
			names.add(fn[1]);
			continue;
		}
		const decl = /^local\s+([^=]+?)(?:=|$)/.exec(line);
		if (!decl) continue;
		for (const raw of decl[1].split(',')) {
			const name = raw.trim();
			if (/^[A-Za-z_]\w*$/.test(name)) names.add(name);
		}
	}
	return names;
}

// Every local a file declares, at any depth. A file that makes its own `Value`
// inside a run(function() ... end) is not reading some other file's `Value`, so
// these have to be subtracted from its reads or near-everything looks circular.
function allLocals(code) {
	const names = new Set();
	const re = /\blocal\s+(?:function\s+([A-Za-z_]\w*)|([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*))/g;
	let m;
	while ((m = re.exec(code)) !== null) {
		if (m[1]) {
			names.add(m[1]);
			continue;
		}
		for (const raw of m[2].split(',')) names.add(raw.trim());
	}
	return names;
}

// Identifiers a file reads. Field accesses (a.b, a:b) and table keys ({k = v})
// are skipped -- they share a namespace with nothing and would invent edges.
function referencedNames(code) {
	const names = new Set();
	const re = /([.:]?)\s*\b([A-Za-z_]\w*)\b\s*(=?)(=?)/g;
	let m;
	while ((m = re.exec(code)) !== null) {
		const [, accessor, name, eq1, eq2] = m;
		if (accessor === '.' || accessor === ':') continue;
		if (LUA_KEYWORDS.has(name)) continue;
		// `name =` (but not `==`) preceded by { or , is a table key
		if (eq1 === '=' && eq2 !== '=') {
			const before = code.slice(0, m.index).replace(/\s+$/, '');
			const prev = before[before.length - 1];
			if (prev === '{' || prev === ',') continue;
		}
		names.add(name);
	}
	return names;
}

function collectFiles(gameDir) {
	const base = path.join(gameDir, 'base.lua');
	if (!fs.existsSync(base)) {
		throw new Error(`no base.lua in ${gameDir}`);
	}
	const modules = [];
	for (const entry of fs.readdirSync(gameDir, { withFileTypes: true })) {
		if (!entry.isDirectory()) continue;
		const dir = path.join(gameDir, entry.name);
		for (const file of fs.readdirSync(dir).sort()) {
			if (file.endsWith('.lua')) modules.push(path.join(dir, file));
		}
	}
	modules.sort();
	return { base, modules };
}

// Order modules so declarations land before the files that read them, keeping
// the alphabetical order wherever nothing forces a swap.
function orderModules(files, sources) {
	const declares = new Map();
	const reads = new Map();
	const owned = new Map();
	for (const f of files) {
		const code = stripNonCode(sources.get(f));
		declares.set(f, chunkScopeLocals(code));
		owned.set(f, allLocals(code));
		reads.set(f, referencedNames(code));
	}

	const owner = new Map();
	for (const f of files) {
		for (const name of declares.get(f)) {
			if (!owner.has(name)) owner.set(name, []);
			owner.get(name).push(f);
		}
	}

	const deps = new Map(files.map(f => [f, new Set()]));
	for (const f of files) {
		for (const name of reads.get(f)) {
			if (owned.get(f).has(name)) continue; // its own local, at whatever depth
			for (const src of owner.get(name) || []) {
				if (src !== f) deps.get(f).add(src);
			}
		}
	}

	const ordered = [];
	const state = new Map(); // unvisited | visiting | done
	const cycles = [];
	const visit = (f, trail) => {
		if (state.get(f) === 'done') return;
		if (state.get(f) === 'visiting') {
			cycles.push([...trail.slice(trail.indexOf(f)), f].map(p => path.basename(p)));
			return;
		}
		state.set(f, 'visiting');
		for (const d of [...deps.get(f)].sort()) visit(d, [...trail, f]);
		state.set(f, 'done');
		ordered.push(f);
	};
	for (const f of files) visit(f, []);

	return { ordered, cycles, declares };
}

function main() {
	const argv = process.argv.slice(2);
	const outFlag = argv.findIndex(a => a === '-o' || a === '--out');
	let out = null;
	if (outFlag !== -1) {
		out = argv[outFlag + 1];
		argv.splice(outFlag, 2);
	}
	const gameDir = argv[0];
	if (!gameDir) {
		console.error('usage: node tools/bundlegame.js "src/games/<place id> - <name>" [-o out.lua]');
		process.exit(1);
	}

	const placeId = (path.basename(gameDir).match(/^(\d+)/) || [])[1];
	if (!out) {
		if (!placeId) throw new Error(`cannot infer place id from "${path.basename(gameDir)}", pass -o`);
		out = `${placeId}.lua`;
	}

	const { base, modules } = collectFiles(gameDir);
	const sources = new Map();
	for (const f of [base, ...modules]) {
		sources.set(f, fs.readFileSync(f, 'utf8'));
	}

	const { ordered, cycles, declares } = orderModules(modules, sources);
	for (const cycle of cycles) {
		console.warn(`warning: circular reference between ${cycle.join(' -> ')}, order may be wrong`);
	}

	const final = [base, ...ordered];

	// Concatenation puts every module's chunk-scope locals in one function, and
	// Luau caps that. Past the limit the bundle will not load at all, so refuse
	// to write one rather than hand over a file that fails at runtime.
	let localCount = chunkScopeLocals(stripNonCode(sources.get(base))).size;
	for (const f of ordered) localCount += declares.get(f).size;
	if (localCount > LOCAL_LIMIT) {
		console.error(
			`error: ${path.basename(gameDir)} declares ~${localCount} chunk-scope locals, ` +
			`over Luau's per-function limit of ${LOCAL_LIMIT}.\n` +
			'A flat concatenation cannot load. This folder needs the upstream bundler, ' +
			'which scopes each module and hoists only the names shared between them.'
		);
		process.exit(1);
	}

	const parts = [
		`-- ${path.basename(gameDir)}`,
		'-- Bundled by tools/bundlegame.js -- edit the files under src/games, not this.',
		''
	];
	for (const f of final) {
		parts.push(`-- ${'='.repeat(60)}`);
		parts.push(`-- ${path.relative(gameDir, f)}`);
		parts.push(`-- ${'='.repeat(60)}`);
		parts.push(sources.get(f).replace(/\s*$/, ''));
		parts.push('');
	}

	fs.writeFileSync(out, parts.join('\n'));

	console.log(`bundled ${final.length} files -> ${out}  (~${localCount}/${LOCAL_LIMIT} locals)`);
	for (const f of final) console.log(`  ${path.relative(gameDir, f)}`);
}

main();
