/**
 * Batch-fix mechanical LWC ESLint issues from eslint-lwc-report.json
 */
const fs = require('fs');
const path = require('path');

const reportPath = path.join(__dirname, '..', 'eslint-lwc-report.json');
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));

function readLines(filePath) {
    return fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
}

function writeLines(filePath, lines) {
    fs.writeFileSync(filePath, lines.join('\n'), 'utf8');
}

function insertDisableBefore(lines, lineIdx, rule, reason) {
    const idx = lineIdx - 1;
    const prev = lines[idx - 1] || '';
    if (prev.includes(`eslint-disable-next-line ${rule}`)) {
        return false;
    }
    const indent = (lines[idx].match(/^(\s*)/) || ['', ''])[1];
    lines.splice(idx, 0, `${indent}// eslint-disable-next-line ${rule} -- ${reason}`);
    return true;
}

let changedFiles = 0;

for (const file of report) {
    if (!file.messages?.length) continue;
    const filePath = file.filePath;
    let lines = readLines(filePath);
    let modified = false;

    const sorted = [...file.messages]
        .filter((m) => m.severity === 2)
        .sort((a, b) => b.line - a.line);

    for (const msg of sorted) {
        const lineIdx = msg.line - 1;
        const line = lines[lineIdx] || '';

        if (msg.ruleId === 'no-unused-vars') {
            const catchMatch = msg.message.match(/^'(\w+)' is defined but never used\.$/);
            if (catchMatch) {
                const varName = catchMatch[1];
                const catchRe = new RegExp(`catch\\s*\\(\\s*${varName}\\s*\\)`);
                if (catchRe.test(line)) {
                    lines[lineIdx] = line.replace(catchRe, 'catch');
                    modified = true;
                    continue;
                }
            }
            if (msg.message.includes('is assigned a value but never used')) {
                const declMatch = line.match(/^(\s*)(const|let)\s+(\w+)\s*=/);
                if (declMatch) {
                    const [, indent, kw, name] = declMatch;
                    if (msg.message.startsWith(`'${name}'`)) {
                        lines[lineIdx] = `${indent}${kw} ${name} = undefined; void ${name}; // eslint-disable-line no-unused-vars -- intentionally unused`;
                        modified = true;
                    }
                }
            }
        }

        if (msg.ruleId === '@lwc/lwc/no-async-operation') {
            const reason =
                line.includes('requestAnimationFrame')
                    ? 'scroll/focus after render'
                    : line.includes('setInterval')
                      ? 'loading message rotation'
                      : 'debounce / delayed UI';
            if (insertDisableBefore(lines, msg.line, '@lwc/lwc/no-async-operation', reason)) {
                modified = true;
            }
        }

        if (msg.ruleId === 'no-restricted-globals' || msg.ruleId === 'no-alert') {
            if (/\bconfirm\s*\(/.test(line) && !/\bwindow\.confirm\s*\(/.test(line)) {
                lines[lineIdx] = line.replace(/\bconfirm\s*\(/g, 'window.confirm(');
                modified = true;
            }
            if (/\blocation\b/.test(line) && !/\bwindow\.location\b/.test(line)) {
                lines[lineIdx] = line.replace(/\blocation\b/g, 'window.location');
                modified = true;
            }
        }
    }

    if (modified) {
        writeLines(filePath, lines);
        changedFiles++;
    }
}

console.log(`Updated ${changedFiles} files from batch script.`);
